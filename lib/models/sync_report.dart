import 'folder_pair.dart';

enum SyncPhase {
  scanningLocal,
  listingRemote,
  hashing,
  transferring,
  finishing,
}

/// Progreso de una sincronización en curso, para mostrarlo en la interfaz.
class SyncProgress {
  const SyncProgress({
    required this.phase,
    this.completed = 0,
    this.total = 0,
    this.currentPath,
  });

  final SyncPhase phase;
  final int completed;
  final int total;
  final String? currentPath;

  double? get fraction =>
      phase == SyncPhase.transferring && total > 0 ? completed / total : null;

  String describe() {
    switch (phase) {
      case SyncPhase.scanningLocal:
        return 'Analizando carpeta local…';
      case SyncPhase.listingRemote:
        return 'Consultando Google Drive…';
      case SyncPhase.hashing:
        return 'Comparando contenidos…';
      case SyncPhase.transferring:
        final file = currentPath == null ? '' : ' · $currentPath';
        return '$completed de $total$file';
      case SyncPhase.finishing:
        return 'Finalizando…';
    }
  }
}

/// Resultado de sincronizar un emparejamiento.
class SyncReport {
  SyncReport({required this.startedAt});

  final DateTime startedAt;
  DateTime? finishedAt;
  int uploaded = 0;
  int downloaded = 0;
  int deletedLocal = 0;
  int deletedRemote = 0;
  int conflicts = 0;
  bool cancelled = false;

  /// Error que abortó la sincronización completa (sin conexión, sin permisos…).
  String? fatalError;

  /// Errores de archivos concretos; el resto de la sincronización continúa.
  final List<String> errors = [];

  int get changes =>
      uploaded + downloaded + deletedLocal + deletedRemote + conflicts;

  SyncOutcome get outcome {
    if (fatalError != null) return SyncOutcome.failed;
    if (cancelled) return SyncOutcome.cancelled;
    if (errors.isNotEmpty) return SyncOutcome.partial;
    return SyncOutcome.success;
  }

  String get summary {
    if (fatalError != null) return fatalError!;
    final deleted = deletedLocal + deletedRemote;
    final parts = <String>[
      if (uploaded > 0) _count(uploaded, 'subido', 'subidos'),
      if (downloaded > 0) _count(downloaded, 'descargado', 'descargados'),
      if (deleted > 0) _count(deleted, 'eliminado', 'eliminados'),
      if (conflicts > 0) _count(conflicts, 'conflicto', 'conflictos'),
      if (errors.isNotEmpty) _count(errors.length, 'error', 'errores'),
    ];
    final text = parts.isEmpty ? 'Todo al día' : parts.join(' · ');
    return cancelled ? 'Cancelada · $text' : text;
  }

  static String _count(int n, String singular, String plural) =>
      '$n ${n == 1 ? singular : plural}';
}
