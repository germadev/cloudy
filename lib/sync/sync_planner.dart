import '../models/folder_pair.dart';
import '../models/sync_state.dart';
import 'local_scanner.dart';
import 'remote_drive.dart';

enum SyncActionType {
  /// Subir un archivo local que no existe en Drive.
  upload,

  /// Subir una nueva versión de un archivo que ya existe en Drive.
  updateRemote,

  /// Descargar (o sobrescribir) el archivo local con la versión de Drive.
  download,

  /// Borrar el archivo local porque se borró en Drive.
  deleteLocal,

  /// Enviar a la papelera de Drive porque se borró en local.
  trashRemote,

  /// Ambos lados cambiaron: conservar las dos versiones.
  keepBoth,

  /// Ambos lados coinciden: solo hay que registrar el estado.
  markSynced,

  /// Olvidar el estado guardado de una ruta que ya no se sincroniza.
  forget,
}

class SyncAction {
  const SyncAction(this.type, this.path);

  final SyncActionType type;
  final String path;

  /// Si la acción transfiere o borra datos (y por tanto cuenta como progreso).
  bool get isTransfer =>
      type != SyncActionType.markSynced && type != SyncActionType.forget;

  @override
  String toString() => '${type.name}($path)';

  @override
  bool operator ==(Object other) =>
      other is SyncAction && other.type == type && other.path == path;

  @override
  int get hashCode => Object.hash(type, path);
}

/// Calcula las acciones necesarias para reconciliar ambos lados, comparando
/// el estado actual con el registrado tras la última sincronización.
///
/// Es una función pura: no toca el disco ni la red, lo que permite probar
/// todas las combinaciones de cambios de forma aislada.
List<SyncAction> planSync({
  required Map<String, LocalFile> local,
  required Map<String, RemoteFile> remote,
  required Map<String, FileSyncState> previous,
  required SyncMode mode,
  ConflictPolicy conflictPolicy = ConflictPolicy.keepBoth,
  bool propagateDeletions = true,
}) {
  final paths = {...local.keys, ...remote.keys, ...previous.keys}.toList()
    ..sort();
  final actions = <SyncAction>[];

  void add(SyncActionType type, String path) =>
      actions.add(SyncAction(type, path));

  for (final path in paths) {
    final l = local[path];
    final r = remote[path];
    final s = previous[path];

    if (l != null && r != null) {
      if (l.md5 != null && l.md5 == r.md5) {
        // Mismo contenido: basta con actualizar el estado si está desfasado.
        if (s == null || _localChanged(l, s) || _remoteChanged(r, s)) {
          add(SyncActionType.markSynced, path);
        }
        continue;
      }
      if (s == null) {
        add(_resolveConflict(mode, conflictPolicy, l, r), path);
        continue;
      }
      final localChanged = _localChanged(l, s);
      final remoteChanged = _remoteChanged(r, s);
      if (localChanged && remoteChanged) {
        add(_resolveConflict(mode, conflictPolicy, l, r), path);
      } else if (localChanged && mode.uploads) {
        add(SyncActionType.updateRemote, path);
      } else if (remoteChanged && mode.downloads) {
        add(SyncActionType.download, path);
      }
    } else if (l != null) {
      if (s == null) {
        if (mode.uploads) add(SyncActionType.upload, path);
        continue;
      }
      // Existía en Drive y ya no.
      final localChanged = _localChanged(l, s);
      switch (mode) {
        case SyncMode.twoWay:
          add(
            propagateDeletions && !localChanged
                ? SyncActionType.deleteLocal
                : SyncActionType.upload,
            path,
          );
        case SyncMode.uploadOnly:
          // Drive es la copia de seguridad: se restaura.
          add(SyncActionType.upload, path);
        case SyncMode.downloadOnly:
          add(
            propagateDeletions && !localChanged
                ? SyncActionType.deleteLocal
                : SyncActionType.forget,
            path,
          );
      }
    } else if (r != null) {
      if (s == null) {
        if (mode.downloads) add(SyncActionType.download, path);
        continue;
      }
      // Existía en local y ya no.
      final remoteChanged = _remoteChanged(r, s);
      switch (mode) {
        case SyncMode.twoWay:
          add(
            propagateDeletions && !remoteChanged
                ? SyncActionType.trashRemote
                : SyncActionType.download,
            path,
          );
        case SyncMode.uploadOnly:
          add(
            propagateDeletions && !remoteChanged
                ? SyncActionType.trashRemote
                : SyncActionType.forget,
            path,
          );
        case SyncMode.downloadOnly:
          add(SyncActionType.download, path);
      }
    } else {
      // Borrado en ambos lados.
      add(SyncActionType.forget, path);
    }
  }
  return actions;
}

bool _localChanged(LocalFile l, FileSyncState s) =>
    l.modifiedMs != s.localModifiedMs || l.size != s.localSize;

bool _remoteChanged(RemoteFile r, FileSyncState s) {
  if (r.id != s.remoteId) return true;
  if (r.md5 != null && s.remoteMd5 != null) return r.md5 != s.remoteMd5;
  return r.modifiedMs != s.remoteModifiedMs;
}

SyncActionType _resolveConflict(
  SyncMode mode,
  ConflictPolicy policy,
  LocalFile l,
  RemoteFile r,
) {
  switch (mode) {
    case SyncMode.uploadOnly:
      return SyncActionType.updateRemote;
    case SyncMode.downloadOnly:
      return SyncActionType.download;
    case SyncMode.twoWay:
      switch (policy) {
        case ConflictPolicy.keepBoth:
          return SyncActionType.keepBoth;
        case ConflictPolicy.preferLocal:
          return SyncActionType.updateRemote;
        case ConflictPolicy.preferRemote:
          return SyncActionType.download;
        case ConflictPolicy.preferNewest:
          return l.modifiedMs >= r.modifiedMs
              ? SyncActionType.updateRemote
              : SyncActionType.download;
      }
  }
}
