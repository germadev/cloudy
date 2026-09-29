import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/app_settings.dart';
import '../models/folder_pair.dart';
import '../models/log_entry.dart';
import '../models/stored_account.dart';
import '../models/sync_state.dart';
import '../sync/sync_engine.dart';
import '../sync/sync_lock.dart';

/// Persistencia en archivos JSON dentro del directorio privado de la app.
///
/// Se usa tanto desde la interfaz como desde la tarea en segundo plano (otro
/// isolate), por eso cada modificación relee el archivo antes de escribirlo.
class AppStorage implements SyncStateStore {
  AppStorage(this.directory);

  static const maxLogEntries = 200;

  final Directory directory;

  static Future<AppStorage> open() async =>
      AppStorage(await getApplicationSupportDirectory());

  File get _pairsFile => File(p.join(directory.path, 'folder_pairs.json'));
  File get _settingsFile => File(p.join(directory.path, 'settings.json'));
  File get _logFile => File(p.join(directory.path, 'activity_log.json'));
  File get _accountFile => File(p.join(directory.path, 'account.json'));
  File _stateFile(String pairId) =>
      File(p.join(directory.path, 'state', '$pairId.json'));

  SyncLock createSyncLock() =>
      SyncLock(File(p.join(directory.path, 'sync.lock')));

  // Emparejamientos.

  Future<List<FolderPair>> loadPairs() async {
    final data = await _readJson(_pairsFile);
    if (data is! List) return [];
    return [
      for (final item in data)
        FolderPair.fromJson(item as Map<String, dynamic>),
    ];
  }

  Future<void> savePairs(List<FolderPair> pairs) =>
      _writeJson(_pairsFile, [for (final pair in pairs) pair.toJson()]);

  /// Inserta o reemplaza un emparejamiento.
  Future<List<FolderPair>> upsertPair(FolderPair pair) async {
    final pairs = await loadPairs();
    final index = pairs.indexWhere((e) => e.id == pair.id);
    if (index == -1) {
      pairs.add(pair);
    } else {
      pairs[index] = pair;
    }
    await savePairs(pairs);
    return pairs;
  }

  /// Aplica [update] sobre la versión más reciente guardada en disco.
  Future<List<FolderPair>> updatePair(
    String id,
    FolderPair Function(FolderPair current) update,
  ) async {
    final pairs = await loadPairs();
    final index = pairs.indexWhere((e) => e.id == id);
    if (index != -1) {
      pairs[index] = update(pairs[index]);
      await savePairs(pairs);
    }
    return pairs;
  }

  Future<List<FolderPair>> removePair(String id) async {
    final pairs = await loadPairs()
      ..removeWhere((e) => e.id == id);
    await savePairs(pairs);
    final state = _stateFile(id);
    if (await state.exists()) await state.delete();
    return pairs;
  }

  // Estado de sincronización.

  @override
  Future<Map<String, FileSyncState>> loadState(String pairId) async {
    final data = await _readJson(_stateFile(pairId));
    if (data is! Map<String, dynamic>) return {};
    return data.map(
      (path, value) =>
          MapEntry(path, FileSyncState.fromJson(value as Map<String, dynamic>)),
    );
  }

  @override
  Future<void> saveState(String pairId, Map<String, FileSyncState> state) =>
      _writeJson(
        _stateFile(pairId),
        state.map((path, value) => MapEntry(path, value.toJson())),
      );

  Future<void> clearState(String pairId) async {
    final file = _stateFile(pairId);
    if (await file.exists()) await file.delete();
  }

  // Ajustes.

  Future<AppSettings> loadSettings() async {
    final data = await _readJson(_settingsFile);
    return data is Map<String, dynamic>
        ? AppSettings.fromJson(data)
        : const AppSettings();
  }

  Future<void> saveSettings(AppSettings settings) =>
      _writeJson(_settingsFile, settings.toJson());

  // Cuenta.

  Future<StoredAccount?> loadAccount() async {
    final data = await _readJson(_accountFile);
    return data is Map<String, dynamic> ? StoredAccount.fromJson(data) : null;
  }

  Future<void> saveAccount(StoredAccount account) =>
      _writeJson(_accountFile, account.toJson());

  Future<void> clearAccount() async {
    if (await _accountFile.exists()) await _accountFile.delete();
  }

  // Registro de actividad.

  Future<List<LogEntry>> loadLog() async {
    final data = await _readJson(_logFile);
    if (data is! List) return [];
    return [
      for (final item in data) LogEntry.fromJson(item as Map<String, dynamic>),
    ];
  }

  Future<List<LogEntry>> appendLog(LogEntry entry) async {
    final entries = [entry, ...await loadLog()];
    final trimmed = entries.take(maxLogEntries).toList();
    await _writeJson(_logFile, [for (final e in trimmed) e.toJson()]);
    return trimmed;
  }

  Future<void> clearLog() => _writeJson(_logFile, const []);

  // Utilidades.

  Future<Object?> _readJson(File file) async {
    try {
      if (!await file.exists()) return null;
      return jsonDecode(await file.readAsString());
    } on FormatException {
      return null;
    }
  }

  /// Escribe de forma atómica: primero a un temporal y después lo renombra,
  /// para no dejar un JSON corrupto si la app muere a mitad de escritura.
  Future<void> _writeJson(File file, Object? data) async {
    await file.parent.create(recursive: true);
    final tmp = File(
      '${file.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    await tmp.writeAsString(jsonEncode(data), flush: true);
    await tmp.rename(file.path);
  }
}
