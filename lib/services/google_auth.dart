import 'dart:async';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

import '../sync/remote_drive.dart';
import 'auth_http_client.dart';

/// Identificadores OAuth, inyectados al compilar con `--dart-define`:
///
/// * `GOOGLE_SERVER_CLIENT_ID`: ID de cliente de tipo «Aplicación web».
///   Obligatorio en Android si no se usa `google-services.json`.
/// * `GOOGLE_IOS_CLIENT_ID`: ID de cliente de iOS (alternativa a declarar
///   `GIDClientID` en `Info.plist`).
class GoogleAuthConfig {
  static const serverClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
  );
  static const iosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');

  /// Acceso completo a Drive: necesario para leer archivos que no ha creado
  /// la propia app (sincronización bidireccional y descargas).
  static const scopes = [drive.DriveApi.driveScope];
}

Future<void>? _initialization;

/// Inicializa `google_sign_in` una sola vez por isolate.
Future<void> initializeGoogleSignIn() {
  return _initialization ??= GoogleSignIn.instance.initialize(
    clientId: GoogleAuthConfig.iosClientId.isEmpty
        ? null
        : GoogleAuthConfig.iosClientId,
    serverClientId: GoogleAuthConfig.serverClientId.isEmpty
        ? null
        : GoogleAuthConfig.serverClientId,
  );
}

/// Pide un token de acceso a Drive sin interacción del usuario. Devuelve null
/// si hace falta que el usuario vuelva a conceder permisos.
Future<String?> fetchDriveAccessToken({String? userId, String? email}) async {
  await initializeGoogleSignIn();
  final tokens = await GoogleSignInPlatform.instance
      .clientAuthorizationTokensForScopes(
        ClientAuthorizationTokensForScopesParameters(
          request: AuthorizationRequestDetails(
            scopes: GoogleAuthConfig.scopes,
            userId: userId,
            email: email,
            promptIfUnauthorized: false,
          ),
        ),
      );
  return tokens?.accessToken;
}

/// Cliente HTTP autenticado para la API de Drive que renueva el token solo.
/// Funciona también desde la tarea en segundo plano, sin interfaz.
http.Client createDriveHttpClient({String? userId, String? email}) {
  final tokens = AccessTokenProvider(
    () async {
      String? token;
      try {
        token = await fetchDriveAccessToken(userId: userId, email: email);
      } on GoogleSignInException catch (e) {
        throw FatalSyncException(
          'No se pudo autorizar el acceso a Google Drive: '
          '${e.description ?? e.code.name}',
        );
      }
      if (token == null) {
        throw const FatalSyncException(
          'Hay que volver a autorizar el acceso a Google Drive. Abre Cloudy.',
        );
      }
      return token;
    },
    onInvalidate: (token) => GoogleSignIn.instance.authorizationClient
        .clearAuthorizationToken(accessToken: token),
  );
  return AuthHttpClient(tokens);
}
