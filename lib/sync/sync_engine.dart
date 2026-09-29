import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../models/folder_pair.dart';
import '../models/sync_report.dart';
import '../models/sync_state.dart';
import 'local_scanner.dart';
import 'path_filter.dart';
import 'remote_drive.dart';
import 'sync_planner.dart';

/// Persistencia del estado de la última sincronización de cada emparejamiento.
abstract class SyncStateStore {
  Future<Map<String, FileSyncState>> loadState(String pairId);
  Future<void> saveState(String pairId, Map<String, FileSyncState> state);
}

/// Permite detener una sincronización en curso entre dos archivos.
class SyncCancellation {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;
}

typedef ProgressCallback = void Function(SyncProgress progress);

/// Sincroniza una carpeta local con una carpeta remota.
class SyncEngine {
  SyncEngine({
    required this.remote,
    required this.stateStore,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final RemoteDrive remote;
  final SyncStateStore stateStore;
  final DateTime Function() _clock;

  /// Cada cuántas transferencias se guarda el estado, para no repetir trabajo
  /// si el sistema detiene la app a mitad de sincronización.
  static const _saveEvery = 20;

  Future<SyncReport> run(
    FolderPair pair, {
    ProgressCallback? onProgress,
    SyncCancellation? cancellation,
  }) async {
    final report = SyncReport(startedAt: _clock());
    try {
      await _SyncRun(this, pair, report, onProgress, cancellation).execute();
    } on FatalSyncException catch (e) {
      report.fatalError = e.message;
    }
    report.finishedAt = _clock();
    return report;
  }
}

class _SyncRun {
  _SyncRun(
    this.engine,
    this.pair,
    this.report,
    this.onProgress,
    this.cancellation,
  );

  final SyncEngine engine;
  final FolderPair pair;
  final SyncReport report;
  final ProgressCallback? onProgress;
  final SyncCancellation? cancellation;

  late final Map<String, LocalFile> local;
  late final RemoteTree tree;
  late final Map<String, FileSyncState> state;
  final Set<String> _remoteFoldersToCheck = {};

  RemoteDrive get remote => engine.remote;
  String get root => pair.localPath;

  void _progress(SyncPhase phase, {int done = 0, int total = 0, String? path}) {
    onProgress?.call(
      SyncProgress(
        phase: phase,
        completed: done,
        total: total,
        currentPath: path,
      ),
    );
  }

  Future<void> execute() async {
    final filter = PathFilter(
      excludePatterns: pair.excludePatterns,
      includeHidden: pair.includeHidden,
    );

    final rootDir = Directory(root);
    if (!await rootDir.exists()) {
      throw FatalSyncException(
        'La carpeta local no existe o no es accesible: $root',
      );
    }

    _progress(SyncPhase.scanningLocal);
    try {
      local = await scanLocalFolder(rootDir, filter);
    } on FileSystemException catch (e) {
      throw FatalSyncException(
        'No se puede leer la carpeta local (${e.osError?.message ?? e.message}). '
        'Revisa los permisos de acceso a archivos.',
      );
    }

    _progress(SyncPhase.listingRemote);
    try {
      tree = await remote.listTree(
        pair.remoteFolderId,
        include: (path, _) => filter.includes(path),
      );
    } on FatalSyncException {
      rethrow;
    } catch (e) {
      throw FatalSyncException('No se pudo consultar Google Drive: $e');
    }
    report.errors.addAll(tree.warnings);

    state = Map.of(await engine.stateStore.loadState(pair.id));

    _checkSafety();

    await _hashCandidates();

    final actions = planSync(
      local: local,
      remote: tree.files,
      previous: state,
      mode: pair.mode,
      conflictPolicy: pair.conflictPolicy,
      propagateDeletions: pair.propagateDeletions,
    );

    try {
      await _apply(actions);
      await _cleanupRemoteFolders();
    } finally {
      _progress(SyncPhase.finishing);
      await engine.stateStore.saveState(pair.id, state);
    }
  }

  /// Evita catástrofes cuando un lado aparece vacío de repente (tarjeta SD
  /// desmontada, permisos revocados, carpeta de Drive movida…): sin esta
  /// comprobación se borraría todo el contenido del otro lado.
  void _checkSafety() {
    if (state.isEmpty || !pair.propagateDeletions) return;
    if (local.isEmpty && tree.files.isNotEmpty && pair.mode.uploads) {
      throw const FatalSyncException(
        'La carpeta local está vacía pero antes tenía archivos. Se ha detenido '
        'la sincronización para no borrar nada en Drive. Si el vaciado es '
        'intencionado, desactiva «Propagar eliminaciones» y vuelve a sincronizar.',
      );
    }
    if (tree.files.isEmpty && local.isNotEmpty && pair.mode.downloads) {
      throw const FatalSyncException(
        'La carpeta de Drive está vacía pero antes tenía archivos. Se ha '
        'detenido la sincronización para no borrar nada en el dispositivo. Si '
        'el vaciado es intencionado, desactiva «Propagar eliminaciones» y '
        'vuelve a sincronizar.',
      );
    }
  }

  /// Calcula el MD5 de los archivos locales que existen también en Drive y
  /// cuyo estado es desconocido o ha cambiado, para no transferir archivos
  /// idénticos ni generar conflictos falsos.
  Future<void> _hashCandidates() async {
    final candidates = [
      for (final entry in local.entries)
        if (tree.files[entry.key]?.md5 != null &&
            _needsHash(entry.value, state[entry.key]))
          entry.key,
    ];
    for (var i = 0; i < candidates.length; i++) {
      if (cancellation?.isCancelled ?? false) return;
      final path = candidates[i];
      _progress(
        SyncPhase.hashing,
        done: i,
        total: candidates.length,
        path: path,
      );
      try {
        local[path]!.md5 = await md5OfFile(fileAt(root, path));
      } on FileSystemException {
        // Si no se puede leer, el planificador lo tratará como distinto.
      }
    }
  }

  bool _needsHash(LocalFile file, FileSyncState? s) =>
      s == null ||
      s.localModifiedMs != file.modifiedMs ||
      s.localSize != file.size;

  Future<void> _apply(List<SyncAction> actions) async {
    final transfers = actions.where((a) => a.isTransfer).length;
    var done = 0;
    var sinceSave = 0;
    for (final action in actions) {
      if (cancellation?.isCancelled ?? false) {
        report.cancelled = true;
        return;
      }
      if (action.isTransfer) {
        _progress(
          SyncPhase.transferring,
          done: done,
          total: transfers,
          path: action.path,
        );
      }
      try {
        await _perform(action);
      } on FatalSyncException {
        rethrow;
      } catch (e) {
        report.errors.add('${action.path}: ${_describeError(e)}');
      }
      if (action.isTransfer) {
        done++;
        if (++sinceSave >= SyncEngine._saveEvery) {
          sinceSave = 0;
          await engine.stateStore.saveState(pair.id, state);
        }
      }
    }
    _progress(SyncPhase.transferring, done: done, total: transfers);
  }

  Future<void> _perform(SyncAction action) async {
    final path = action.path;
    switch (action.type) {
      case SyncActionType.upload:
        await _upload(path);
        report.uploaded++;
      case SyncActionType.updateRemote:
        final existing = tree.files[path]!;
        final file = fileAt(root, path);
        final stat = await _statUnchanged(path, file);
        final uploaded = await remote.uploadUpdate(
          fileId: existing.id,
          source: file,
        );
        _record(path, stat, uploaded);
        report.uploaded++;
      case SyncActionType.download:
        await _download(path, tree.files[path]!);
        report.downloaded++;
      case SyncActionType.deleteLocal:
        final file = fileAt(root, path);
        await _statUnchanged(path, file);
        await file.delete();
        state.remove(path);
        await _cleanupLocalDirs(file.parent);
        report.deletedLocal++;
      case SyncActionType.trashRemote:
        await remote.trash(tree.files[path]!.id);
        state.remove(path);
        _remoteFoldersToCheck.add(p.posix.dirname(path));
        report.deletedRemote++;
      case SyncActionType.keepBoth:
        await _keepBoth(path);
        report.conflicts++;
      case SyncActionType.markSynced:
        final file = fileAt(root, path);
        _record(path, await file.stat(), tree.files[path]!);
      case SyncActionType.forget:
        state.remove(path);
    }
  }

  Future<void> _upload(String path) async {
    final file = fileAt(root, path);
    final stat = await _statUnchanged(path, file);
    final parentId = await _ensureRemoteFolder(p.posix.dirname(path));
    final uploaded = await remote.uploadNew(
      parentId: parentId,
      name: p.posix.basename(path),
      source: file,
    );
    tree.files[path] = uploaded;
    _record(path, stat, uploaded);
  }

  Future<void> _download(String path, RemoteFile source) async {
    final target = fileAt(root, path);
    if (local.containsKey(path)) {
      // No sobrescribir si el usuario lo modificó durante la sincronización.
      await _statUnchanged(path, target);
    }
    await target.parent.create(recursive: true);
    final partial = File('${target.path}${PathFilter.partialSuffix}');
    try {
      await remote.download(fileId: source.id, target: partial);
      await partial.setLastModified(
        DateTime.fromMillisecondsSinceEpoch(source.modifiedMs),
      );
      await partial.rename(target.path);
    } catch (_) {
      if (await partial.exists()) await partial.delete();
      rethrow;
    }
    _record(path, await target.stat(), source);
  }

  Future<void> _keepBoth(String path) async {
    final original = fileAt(root, path);
    await _statUnchanged(path, original);
    final conflictPath = await _conflictPath(path);
    await original.rename(fileAt(root, conflictPath).path);
    local[conflictPath] = local.remove(path)!;

    await _download(path, tree.files[path]!);
    await _upload(conflictPath);
  }

  Future<String> _conflictPath(String path) async {
    final dir = p.posix.dirname(path);
    final name = p.posix.basename(path);
    final ext = p.posix.extension(name);
    final base = name.substring(0, name.length - ext.length);
    final stamp = DateFormat('yyyy-MM-dd HHmmss').format(engine._clock());
    for (var i = 1; ; i++) {
      final suffix = i == 1 ? '' : ' $i';
      final candidate = '$base (conflicto $stamp$suffix)$ext';
      final full = dir == '.' ? candidate : '$dir/$candidate';
      if (!local.containsKey(full) &&
          !tree.files.containsKey(full) &&
          !await fileAt(root, full).exists()) {
        return full;
      }
    }
  }

  /// Comprueba que el archivo local no ha cambiado desde que se analizó la
  /// carpeta y devuelve su información actual.
  Future<FileStat> _statUnchanged(String path, File file) async {
    final stat = await file.stat();
    final scanned = local[path];
    if (stat.type == FileSystemEntityType.notFound) {
      throw const FileSystemException('el archivo ya no existe');
    }
    if (scanned != null &&
        (stat.size != scanned.size ||
            stat.modified.millisecondsSinceEpoch != scanned.modifiedMs)) {
      throw const FileSystemException(
        'se modificó durante la sincronización; se reintentará la próxima vez',
      );
    }
    return stat;
  }

  void _record(String path, FileStat localStat, RemoteFile remoteFile) {
    state[path] = FileSyncState(
      localModifiedMs: localStat.modified.millisecondsSinceEpoch,
      localSize: localStat.size,
      remoteId: remoteFile.id,
      remoteMd5: remoteFile.md5,
      remoteModifiedMs: remoteFile.modifiedMs,
    );
  }

  Future<String> _ensureRemoteFolder(String dir) async {
    final key = dir == '.' ? '' : dir;
    final known = tree.folders[key];
    if (known != null) return known;
    final parentId = await _ensureRemoteFolder(p.posix.dirname(key));
    final folder = await remote.createFolder(
      parentId: parentId,
      name: p.posix.basename(key),
    );
    tree.folders[key] = folder.id;
    return folder.id;
  }

  /// Tras borrar un archivo local, elimina las carpetas que hayan quedado
  /// vacías si tampoco existen ya en Drive.
  Future<void> _cleanupLocalDirs(Directory dir) async {
    final rootPath = p.normalize(root);
    var current = dir;
    while (p.isWithin(rootPath, current.path)) {
      final relative = toRelativePath(rootPath, current.path);
      if (tree.folders.containsKey(relative)) return;
      if (!await current.exists() || !await current.list().isEmpty) return;
      await current.delete();
      current = current.parent;
    }
  }

  /// Envía a la papelera las carpetas de Drive que se han quedado vacías tras
  /// propagar borrados y que ya no existen en local.
  Future<void> _cleanupRemoteFolders() async {
    final pending = <String>{};
    for (var dir in _remoteFoldersToCheck) {
      while (dir != '.' && dir.isNotEmpty) {
        pending.add(dir);
        dir = p.posix.dirname(dir);
      }
    }
    // De la más profunda a la más superficial.
    final ordered = pending.toList()
      ..sort((a, b) => b.split('/').length.compareTo(a.split('/').length));
    for (final dir in ordered) {
      final id = tree.folders[dir];
      if (id == null) continue;
      if (await Directory(fileAt(root, dir).path).exists()) continue;
      try {
        if (await remote.isFolderEmpty(id)) {
          await remote.trash(id);
          tree.folders.remove(dir);
        }
      } on FatalSyncException {
        rethrow;
      } catch (e) {
        report.errors.add('$dir/: ${_describeError(e)}');
      }
    }
  }

  String _describeError(Object e) {
    if (e is FileSystemException) {
      final os = e.osError?.message;
      return os == null || os.isEmpty ? e.message : '${e.message} ($os)';
    }
    return e.toString();
  }
}
