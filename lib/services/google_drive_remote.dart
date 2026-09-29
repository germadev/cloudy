import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

import '../sync/remote_drive.dart';

/// Implementación de [RemoteDrive] sobre la API v3 de Google Drive.
class GoogleDriveRemote implements RemoteDrive {
  GoogleDriveRemote(http.Client client) : _api = drive.DriveApi(client);

  static const folderMimeType = 'application/vnd.google-apps.folder';
  static const _googleAppsPrefix = 'application/vnd.google-apps.';
  static const _fileFields = 'id,name,mimeType,md5Checksum,size,modifiedTime';

  /// A partir de este tamaño se usa la subida reanudable, que envía el
  /// archivo por fragmentos y tolera cortes.
  static const _resumableThreshold = 5 * 1024 * 1024;
  static const _maxRetries = 4;

  final drive.DriveApi _api;
  final _random = Random();

  @override
  Future<RemoteTree> listTree(
    String rootId, {
    bool Function(String relativePath, bool isFolder)? include,
  }) async {
    final tree = RemoteTree(rootId: rootId);
    final pending = <(String, String)>[('', rootId)];
    while (pending.isNotEmpty) {
      final (folderPath, folderId) = pending.removeLast();
      final children = await _listAll(
        "'$folderId' in parents and trashed = false",
        orderBy: 'modifiedTime desc',
      );
      for (final item in children) {
        final name = item.name ?? '';
        final id = item.id;
        if (id == null) continue;
        final path = folderPath.isEmpty ? name : '$folderPath/$name';
        if (name.isEmpty || name == '.' || name == '..' || name.contains('/')) {
          tree.warnings.add(
            '$path: nombre no válido para el dispositivo, se omite',
          );
          continue;
        }
        final mimeType = item.mimeType ?? '';
        if (mimeType == folderMimeType) {
          if (include != null && !include(path, true)) continue;
          if (tree.folders.containsKey(path)) {
            tree.warnings.add(
              '$path: hay varias carpetas con este nombre en Drive, '
              'solo se sincroniza una',
            );
            continue;
          }
          tree.folders[path] = id;
          pending.add((path, id));
        } else if (mimeType.startsWith(_googleAppsPrefix)) {
          // Documentos de Google, accesos directos, etc.: no son archivos
          // binarios descargables.
          continue;
        } else {
          if (include != null && !include(path, false)) continue;
          if (tree.files.containsKey(path)) {
            // Ordenados por fecha descendente: se conserva el más reciente.
            tree.warnings.add(
              '$path: hay varios archivos con este nombre en Drive, '
              'solo se sincroniza el más reciente',
            );
            continue;
          }
          tree.files[path] = _toRemoteFile(item);
        }
      }
    }
    return tree;
  }

  @override
  Future<List<RemoteFolder>> listFolders(String parentId) async {
    final items = await _listAll(
      "'$parentId' in parents and mimeType = '$folderMimeType' "
      'and trashed = false',
      orderBy: 'name',
    );
    return [
      for (final item in items)
        if (item.id != null)
          RemoteFolder(id: item.id!, name: item.name ?? '(sin nombre)'),
    ];
  }

  @override
  Future<RemoteFolder> createFolder({
    required String parentId,
    required String name,
  }) async {
    final created = await _call(
      () => _api.files.create(
        drive.File(name: name, mimeType: folderMimeType, parents: [parentId]),
        supportsAllDrives: true,
        $fields: 'id,name',
      ),
    );
    return RemoteFolder(id: created.id!, name: created.name ?? name);
  }

  @override
  Future<RemoteFile> uploadNew({
    required String parentId,
    required String name,
    required File source,
  }) async {
    final created = await _call(() async {
      final stat = await source.stat();
      return _api.files.create(
        drive.File(
          name: name,
          parents: [parentId],
          modifiedTime: stat.modified.toUtc(),
        ),
        uploadMedia: drive.Media(source.openRead(), stat.size),
        uploadOptions: _uploadOptions(stat.size),
        supportsAllDrives: true,
        $fields: _fileFields,
      );
    });
    return _toRemoteFile(created);
  }

  @override
  Future<RemoteFile> uploadUpdate({
    required String fileId,
    required File source,
  }) async {
    final updated = await _call(() async {
      final stat = await source.stat();
      return _api.files.update(
        drive.File(modifiedTime: stat.modified.toUtc()),
        fileId,
        uploadMedia: drive.Media(source.openRead(), stat.size),
        uploadOptions: _uploadOptions(stat.size),
        supportsAllDrives: true,
        $fields: _fileFields,
      );
    });
    return _toRemoteFile(updated);
  }

  @override
  Future<void> download({required String fileId, required File target}) {
    return _call(() async {
      final media = await _api.files.get(
        fileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
        supportsAllDrives: true,
      ) as drive.Media;
      await media.stream.pipe(target.openWrite());
    });
  }

  @override
  Future<bool> isFolderEmpty(String folderId) async {
    final page = await _call(
      () => _api.files.list(
        q: "'$folderId' in parents and trashed = false",
        pageSize: 1,
        supportsAllDrives: true,
        includeItemsFromAllDrives: true,
        $fields: 'files(id)',
      ),
    );
    return page.files?.isEmpty ?? true;
  }

  @override
  Future<void> trash(String id) async {
    await _call(
      () => _api.files.update(
        drive.File(trashed: true),
        id,
        supportsAllDrives: true,
        $fields: 'id',
      ),
    );
  }

  drive.UploadOptions _uploadOptions(int size) => size > _resumableThreshold
      ? drive.ResumableUploadOptions()
      : drive.UploadOptions.defaultOptions;

  Future<List<drive.File>> _listAll(String query, {String? orderBy}) async {
    final result = <drive.File>[];
    String? pageToken;
    do {
      final page = await _call(
        () => _api.files.list(
          q: query,
          orderBy: orderBy,
          pageSize: 1000,
          pageToken: pageToken,
          spaces: 'drive',
          supportsAllDrives: true,
          includeItemsFromAllDrives: true,
          $fields: 'nextPageToken,files($_fileFields)',
        ),
      );
      result.addAll(page.files ?? const []);
      pageToken = page.nextPageToken;
    } while (pageToken != null);
    return result;
  }

  RemoteFile _toRemoteFile(drive.File file) => RemoteFile(
    id: file.id!,
    name: file.name ?? '',
    size: int.tryParse(file.size ?? '') ?? 0,
    md5: file.md5Checksum,
    modifiedMs: file.modifiedTime?.millisecondsSinceEpoch ?? 0,
  );

  /// Ejecuta una petición reintentando con espera exponencial los errores
  /// transitorios (límites de uso, errores 5xx, cortes de red).
  Future<T> _call<T>(Future<T> Function() request) async {
    for (var attempt = 0; ; attempt++) {
      try {
        return await request();
      } on drive.DetailedApiRequestError catch (e) {
        final reasons = {for (final d in e.errors) d.reason};
        if (e.status == 401) {
          if (attempt >= 1) {
            throw const FatalSyncException(
              'Google ha rechazado las credenciales. Abre Cloudy y vuelve a '
              'iniciar sesión.',
            );
          }
        } else if (reasons.contains('storageQuotaExceeded')) {
          throw const FatalSyncException(
            'No queda espacio en tu Google Drive.',
          );
        } else if (!_isTransient(e.status, reasons) || attempt >= _maxRetries) {
          throw RemoteException(
            'Google Drive respondió ${e.status ?? '?'}: ${e.message ?? ''}',
          );
        }
      } on SocketException {
        if (attempt >= _maxRetries) throw _offline();
      } on http.ClientException {
        if (attempt >= _maxRetries) throw _offline();
      } on TimeoutException {
        if (attempt >= _maxRetries) throw _offline();
      }
      final delayMs = 500 * (1 << attempt) + _random.nextInt(500);
      await Future<void>.delayed(Duration(milliseconds: delayMs));
    }
  }

  static bool _isTransient(int? status, Set<String?> reasons) =>
      status == 429 ||
      (status != null && status >= 500) ||
      (status == 403 &&
          (reasons.contains('rateLimitExceeded') ||
              reasons.contains('userRateLimitExceeded')));

  static FatalSyncException _offline() => const FatalSyncException(
    'No hay conexión con Google Drive. Se reintentará más tarde.',
  );
}
