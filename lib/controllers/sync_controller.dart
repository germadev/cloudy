import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../models/app_settings.dart';
import '../models/folder_pair.dart';
import '../models/log_entry.dart';
import '../models/sync_report.dart';
import '../services/app_storage.dart';
import '../services/background_sync.dart';
import '../services/storage_permission.dart';
import '../services/sync_runner.dart';
import '../sync/remote_drive.dart';
import '../sync/sync_engine.dart';

/// Estado de la app para la interfaz: emparejamientos, sincronizaciones en
/// curso, ajustes y registro de actividad.
class SyncController extends ChangeNotifier {
  SyncController({required this.storage, required this.remoteFactory});

  final AppStorage storage;
  final RemoteDrive Function() remoteFactory;

  List<FolderPair> _pairs = [];
  List<LogEntry> _log = [];
  AppSettings _settings = const AppSettings();
  bool _hasStorageAccess = true;
  bool _loaded = false;

  final LinkedHashSet<String> _pending = LinkedHashSet();
  final Map<String, SyncProgress> _progress = {};
  bool _running = false;
  SyncCancellation? _cancellation;

  List<FolderPair> get pairs => List.unmodifiable(_pairs);
  List<LogEntry> get log => List.unmodifiable(_log);
  AppSettings get settings => _settings;
  bool get hasStorageAccess => _hasStorageAccess;
  bool get loaded => _loaded;
  bool get isRunning => _running;

  SyncProgress? progressOf(String pairId) => _progress[pairId];
  bool isPending(String pairId) =>
      _pending.contains(pairId) && !_progress.containsKey(pairId);

  FolderPair? pairById(String id) =>
      _pairs.where((p) => p.id == id).firstOrNull;

  Future<void> load() async {
    _pairs = await storage.loadPairs();
    _log = await storage.loadLog();
    _settings = await storage.loadSettings();
    _hasStorageAccess = await StoragePermission.isGranted();
    _loaded = true;
    notifyListeners();
  }

  /// Relee el disco (p. ej. al volver a primer plano, por si la tarea en
  /// segundo plano ha sincronizado algo).
  Future<void> refresh() => load();

  Future<bool> requestStorageAccess() async {
    _hasStorageAccess = await StoragePermission.request();
    notifyListeners();
    return _hasStorageAccess;
  }

  Future<void> savePair(FolderPair pair) async {
    final previous = pairById(pair.id);
    if (previous != null &&
        (previous.localPath != pair.localPath ||
            previous.remoteFolderId != pair.remoteFolderId)) {
      // Cambia lo que se empareja: el estado anterior ya no es válido.
      await storage.clearState(pair.id);
    }
    _pairs = await storage.upsertPair(pair);
    notifyListeners();
  }

  Future<void> deletePair(String id) async {
    _pending.remove(id);
    _pairs = await storage.removePair(id);
    notifyListeners();
  }

  Future<void> setEnabled(String id, bool enabled) async {
    _pairs = await storage.updatePair(
      id,
      (pair) => pair.copyWith(enabled: enabled),
    );
    notifyListeners();
  }

  Future<String?> syncAll() => sync([for (final pair in _pairs) pair.id]);

  /// Encola la sincronización de los emparejamientos indicados. Devuelve un
  /// mensaje para el usuario si no se pudo completar.
  Future<String?> sync(Iterable<String> pairIds) async {
    _pending.addAll(pairIds);
    notifyListeners();
    if (_running) return null;

    _running = true;
    String? message;
    try {
      final runner = SyncRunner(storage: storage, remote: remoteFactory());
      while (_pending.isNotEmpty) {
        final id = _pending.first;
        final cancellation = _cancellation = SyncCancellation();
        final started = await runner.run(
          [id],
          cancellation: cancellation,
          onProgress: (pair, progress) {
            _progress[pair.id] = progress;
            notifyListeners();
          },
          onReport: (pair, report) {
            _progress.remove(pair.id);
            if (report.fatalError != null) message = report.fatalError;
          },
        );
        _pending.remove(id);
        if (!started) {
          message =
              'Hay una sincronización automática en curso. '
              'Inténtalo de nuevo en unos minutos.';
          break;
        }
        if (cancellation.isCancelled) break;
        _pairs = await storage.loadPairs();
        notifyListeners();
      }
    } catch (e) {
      message = 'Error inesperado: $e';
    } finally {
      _running = false;
      _cancellation = null;
      _pending.clear();
      _progress.clear();
      _pairs = await storage.loadPairs();
      _log = await storage.loadLog();
      notifyListeners();
    }
    return message;
  }

  void cancel() {
    _pending.clear();
    _cancellation?.cancel();
    notifyListeners();
  }

  Future<void> updateSettings(AppSettings settings) async {
    _settings = settings;
    notifyListeners();
    await storage.saveSettings(settings);
    await BackgroundScheduler.apply(settings);
  }

  Future<void> clearLog() async {
    await storage.clearLog();
    _log = [];
    notifyListeners();
  }
}
