import '../models/folder_pair.dart';
import '../models/log_entry.dart';
import '../models/sync_report.dart';
import '../sync/remote_drive.dart';
import '../sync/sync_engine.dart';
import 'app_storage.dart';

/// Sincroniza una lista de emparejamientos, guarda el resultado de cada uno y
/// lo anota en el registro. Lo usan tanto la interfaz como la tarea en segundo
/// plano.
class SyncRunner {
  SyncRunner({required this.storage, required this.remote});

  final AppStorage storage;
  final RemoteDrive remote;

  /// Devuelve false si ya había otra sincronización en curso.
  Future<bool> run(
    List<String> pairIds, {
    bool automatic = false,
    SyncCancellation? cancellation,
    void Function(FolderPair pair, SyncProgress progress)? onProgress,
    void Function(FolderPair pair, SyncReport report)? onReport,
  }) async {
    final lock = storage.createSyncLock();
    if (!await lock.tryAcquire()) return false;
    try {
      final engine = SyncEngine(remote: remote, stateStore: storage);
      for (final id in pairIds) {
        if (cancellation?.isCancelled ?? false) break;
        final pair = (await storage.loadPairs())
            .where((p) => p.id == id)
            .firstOrNull;
        if (pair == null) continue;

        final report = await engine.run(
          pair,
          cancellation: cancellation,
          onProgress: onProgress == null ? null : (p) => onProgress(pair, p),
        );
        await storage.updatePair(
          id,
          (current) => current.copyWith(
            lastSyncAt: report.finishedAt,
            lastOutcome: report.outcome,
            lastMessage: report.summary,
          ),
        );
        if (!automatic ||
            report.changes > 0 ||
            report.outcome != SyncOutcome.success) {
          await storage.appendLog(_logEntry(pair, report, automatic));
        }
        onReport?.call(pair, report);
      }
      return true;
    } finally {
      await lock.release();
    }
  }

  LogEntry _logEntry(FolderPair pair, SyncReport report, bool automatic) {
    final level = switch (report.outcome) {
      SyncOutcome.success || SyncOutcome.cancelled => LogLevel.info,
      SyncOutcome.partial => LogLevel.warning,
      SyncOutcome.failed => LogLevel.error,
    };
    return LogEntry(
      time: report.finishedAt ?? DateTime.now(),
      level: level,
      title: automatic ? '${pair.name} (automática)' : pair.name,
      message: report.summary,
      details: report.errors.take(50).toList(),
    );
  }
}
