import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

/// Acceso a carpetas arbitrarias del almacenamiento compartido.
///
/// En Android 11+ el acceso directo a archivos fuera de las carpetas de la app
/// requiere «Acceso a todos los archivos» (MANAGE_EXTERNAL_STORAGE). En
/// Android 10 o anterior basta con el permiso clásico de almacenamiento.
class StoragePermission {
  static bool get _applies => Platform.isAndroid;

  static Future<bool> isGranted() async {
    if (!_applies) return true;
    final manage = await Permission.manageExternalStorage.status;
    if (manage.isRestricted) return Permission.storage.isGranted;
    return manage.isGranted;
  }

  /// En Android 11+ abre la pantalla de ajustes del sistema; el resultado se
  /// conoce al volver a la app.
  static Future<bool> request() async {
    if (!_applies) return true;
    final manage = await Permission.manageExternalStorage.status;
    if (manage.isRestricted) {
      return (await Permission.storage.request()).isGranted;
    }
    return (await Permission.manageExternalStorage.request()).isGranted;
  }
}
