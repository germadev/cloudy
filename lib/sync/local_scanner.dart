import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'path_filter.dart';

/// Archivo local encontrado al analizar la carpeta sincronizada.
class LocalFile {
  LocalFile({required this.size, required this.modifiedMs, this.md5});

  final int size;
  final int modifiedMs;

  /// Solo se calcula cuando hace falta comparar contenidos con Drive.
  String? md5;
}

/// Recorre [root] y devuelve sus archivos indexados por ruta relativa con `/`
/// como separador. No sigue enlaces simbólicos.
Future<Map<String, LocalFile>> scanLocalFolder(
  Directory root,
  PathFilter filter,
) async {
  final result = <String, LocalFile>{};
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final relative = toRelativePath(root.path, entity.path);
    if (!filter.includes(relative)) continue;
    try {
      final stat = await entity.stat();
      result[relative] = LocalFile(
        size: stat.size,
        modifiedMs: stat.modified.millisecondsSinceEpoch,
      );
    } on FileSystemException {
      // Archivo borrado o inaccesible mientras se recorría la carpeta.
    }
  }
  return result;
}

String toRelativePath(String root, String path) =>
    p.split(p.relative(path, from: root)).join('/');

File fileAt(String root, String relativePath) =>
    File(p.joinAll([root, ...relativePath.split('/')]));

Future<String> md5OfFile(File file) async {
  final digest = await md5.bind(file.openRead()).first;
  return digest.toString();
}
