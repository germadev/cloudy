# Cloudy

Aplicación Flutter que mantiene carpetas del dispositivo sincronizadas con
carpetas de Google Drive.

## Funciones

- **Inicio de sesión con Google** y acceso a Drive mediante OAuth.
- **Varias carpetas emparejadas**: cada carpeta local se asocia a una carpeta de
  Drive elegida con un explorador integrado (se pueden crear carpetas nuevas).
- **Tres modos por carpeta**:
  - *Bidireccional*: los cambios de cualquiera de los dos lados se replican.
  - *Solo subir*: copia de seguridad del dispositivo en Drive.
  - *Solo descargar*: réplica local de una carpeta de Drive.
- **Detección de cambios** comparando con el estado de la última
  sincronización (fecha y tamaño en local, MD5 e id en Drive). Los archivos
  idénticos no se vuelven a transferir aunque cambie su fecha.
- **Resolución de conflictos** configurable: conservar ambas versiones (la
  local se renombra como `nombre (conflicto AAAA-MM-DD HHMMSS).ext`), gana el
  dispositivo, gana Drive o gana la más reciente.
- **Propagación de eliminaciones** opcional. En Drive los archivos van a la
  papelera, nunca se borran definitivamente. Si un lado aparece vacío de
  repente (tarjeta SD desmontada, permisos revocados…) la sincronización se
  detiene en lugar de vaciar el otro lado.
- **Exclusiones** con comodines (`*.tmp`, `cache`, `fotos/*.raw`) y opción de
  incluir o no los archivos ocultos.
- **Sincronización automática en segundo plano** (Android) con WorkManager:
  frecuencia configurable, solo con Wi-Fi y/o solo cargando.
- **Subidas reanudables** para archivos grandes, reintentos con espera
  exponencial ante límites de uso o cortes de red, y renovación automática del
  token de acceso.
- **Registro de actividad** con el detalle de los errores por archivo.

## Estructura

```
lib/
├── main.dart, app.dart          Arranque, tema y selección de pantalla según la sesión
├── models/                      Emparejamientos, estado sincronizado, informes, ajustes
├── sync/                        Núcleo independiente de Flutter y de Google
│   ├── sync_planner.dart        Decide las acciones (función pura, muy probada)
│   ├── sync_engine.dart         Ejecuta el plan: subidas, descargas, conflictos, borrados
│   ├── remote_drive.dart        Interfaz del almacenamiento remoto
│   ├── local_scanner.dart       Recorrido de la carpeta local y MD5
│   ├── path_filter.dart         Exclusiones y archivos ocultos
│   └── sync_lock.dart           Evita sincronizaciones simultáneas (app / segundo plano)
├── services/
│   ├── google_drive_remote.dart RemoteDrive sobre la API v3 de Drive
│   ├── google_auth.dart         Configuración OAuth y cliente HTTP autenticado
│   ├── auth_service.dart        Estado de la sesión para la interfaz
│   ├── sync_runner.dart         Ejecuta y registra sincronizaciones (compartido)
│   ├── background_sync.dart     Tarea periódica de WorkManager
│   ├── app_storage.dart         Persistencia en JSON (escritura atómica)
│   └── storage_permission.dart  Permiso de acceso a archivos en Android
├── controllers/sync_controller.dart  Estado de la app (ChangeNotifier + provider)
└── ui/                          Pantallas: acceso, inicio, editor, selector de Drive, ajustes, actividad
```

## Configuración de Google Cloud

La app necesita un proyecto de Google Cloud con la API de Drive activada:

1. En [Google Cloud Console](https://console.cloud.google.com/) crea un
   proyecto y activa la **Google Drive API**.
2. Configura la **pantalla de consentimiento OAuth**. Añade el ámbito
   `https://www.googleapis.com/auth/drive` y, mientras la app esté en pruebas,
   tu cuenta como usuario de prueba.
3. Crea los **ID de cliente OAuth**:
   - **Aplicación web**: su ID es el `GOOGLE_SERVER_CLIENT_ID` que necesita
     Android.
   - **Android**: paquete `es.germade.cloudy` y la huella SHA-1 del certificado
     con el que firmas (para depuración:
     `keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android`).
   - **iOS** (opcional): bundle `es.germade.cloudy`.

### Android

```bash
flutter run --dart-define=GOOGLE_SERVER_CLIENT_ID=<id-web>.apps.googleusercontent.com
```

Al añadir la primera carpeta, la app pide **«Acceso a todos los archivos»**
(Android 11+), necesario para leer y escribir cualquier carpeta del
almacenamiento compartido.

### iOS

Añade a `ios/Runner/Info.plist` el ID de cliente de iOS y su esquema de URL
invertido:

```xml
<key>GIDClientID</key>
<string>TU_ID_IOS.apps.googleusercontent.com</string>
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>com.googleusercontent.apps.TU_ID_IOS</string>
    </array>
  </dict>
</array>
```

(o pásalo con `--dart-define=GOOGLE_IOS_CLIENT_ID=...` y añade igualmente el
esquema de URL).

## Cómo se sincroniza

Para cada archivo se compara el estado actual de ambos lados con el registrado
tras la última sincronización correcta:

| Situación                       | Bidireccional       | Solo subir          | Solo descargar      |
|---------------------------------|---------------------|---------------------|---------------------|
| Nuevo en el dispositivo         | Se sube             | Se sube             | —                   |
| Nuevo en Drive                  | Se descarga         | —                   | Se descarga         |
| Modificado en el dispositivo    | Se sube             | Se sube             | —                   |
| Modificado en Drive             | Se descarga         | —                   | Se descarga         |
| Modificado en ambos             | Según la política   | Gana el dispositivo | Gana Drive          |
| Borrado en el dispositivo       | Papelera de Drive*  | Papelera de Drive*  | Se restaura         |
| Borrado en Drive                | Se borra en local*  | Se restaura en Drive| Se borra en local*  |

\* Solo si «Propagar eliminaciones» está activo y el otro lado no había
cambiado; si no, el archivo se restaura (o se deja de seguir en los modos
unidireccionales).

El estado se guarda cada 20 transferencias, así que si el sistema detiene la
app a mitad de una sincronización larga no se repite el trabajo hecho. Las
descargas se escriben primero en un archivo `.cloudy-part` y se renombran al
terminar, y no se sobrescribe un archivo local que haya cambiado durante la
sincronización.

## Limitaciones

- Los documentos nativos de Google (Docs, Hojas, Presentaciones) y los accesos
  directos no se sincronizan, porque no son archivos descargables tal cual.
- Las carpetas vacías no se replican; las que quedan vacías tras propagar
  eliminaciones sí se eliminan.
- Si en Drive hay varios archivos con el mismo nombre en una carpeta, solo se
  sincroniza el más reciente (queda anotado en el registro).
- La sincronización automática solo está disponible en Android. En iOS el
  sistema no garantiza ejecuciones periódicas y el acceso a carpetas externas a
  la app no persiste; allí la app funciona en primer plano y es preferible
  sincronizar carpetas dentro de sus propios documentos (visibles en la app
  Archivos).
- El ámbito `drive` completo es un ámbito restringido: para publicar la app,
  Google exige una verificación. Igualmente, Google Play exige justificar el
  permiso `MANAGE_EXTERNAL_STORAGE` (las apps de sincronización de archivos son
  un uso admitido).

## Desarrollo

```bash
flutter pub get
flutter analyze
flutter test
```

## Integración continua y releases

- **`.github/workflows/build.yml`**: en cada pull request y en cada push a
  `main` instala las dependencias, ejecuta el análisis estático y los tests y,
  si pasan, compila el APK de Android y el IPA de iOS, que quedan como
  artefactos de la ejecución.
- **`.github/workflows/release.yml`**: al subir una etiqueta `v*` ejecuta
  `build.yml` y publica una release de GitHub con el APK y el IPA adjuntos.
  Las etiquetas con guion (`v1.2.0-beta.1`) se publican como *pre-release*.

```bash
git tag v1.0.0
git push origin v1.0.0
```

La versión de la app se toma de la etiqueta (sin la `v`); el número de build
es el número de ejecución del workflow.

### Secretos del repositorio (todos opcionales)

| Secreto | Uso |
|---|---|
| `GOOGLE_SERVER_CLIENT_ID` | ID de cliente web de OAuth, necesario para iniciar sesión en Android |
| `GOOGLE_IOS_CLIENT_ID` | ID de cliente de iOS; se añade al `Info.plist` junto con su esquema de URL |
| `ANDROID_KEYSTORE_BASE64` | Keystore de firma en base64 |
| `ANDROID_KEYSTORE_PASSWORD` | Contraseña del keystore |
| `ANDROID_KEY_ALIAS` | Alias de la clave |
| `ANDROID_KEY_PASSWORD` | Contraseña de la clave |

Sin keystore, el APK se firma con una clave de depuración distinta en cada
ejecución: se puede instalar, pero no actualizar una versión anterior, y Google
Sign-In solo funcionará si esa huella está registrada. Para crear un keystore
estable y registrar su SHA-1 en Google Cloud:

```bash
keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 \
  -validity 10000 -alias upload
keytool -list -v -keystore upload-keystore.jks -alias upload   # huella SHA-1
base64 -w0 upload-keystore.jks                                  # valor del secreto
```

En local, la misma firma se usa creando `android/key.properties` (excluido de
git) con `storeFile`, `storePassword`, `keyAlias` y `keyPassword`.

El **IPA se genera sin firmar**, porque firmarlo requiere un certificado y un
perfil de aprovisionamiento de Apple. Para instalarlo hay que volver a firmarlo
(por ejemplo con AltStore o Sideloadly) o distribuirlo por TestFlight.

Las pruebas cubren el planificador (todas las combinaciones de cambios y
modos), el motor completo contra un Drive simulado en memoria y carpetas
temporales reales, los filtros, la persistencia, el bloqueo entre procesos y
las pantallas principales.
