import 'dart:io';

import 'package:cloudy/models/app_settings.dart';
import 'package:cloudy/models/folder_pair.dart';
import 'package:cloudy/models/log_entry.dart';
import 'package:cloudy/models/sync_state.dart';
import 'package:cloudy/services/app_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temp;
  late AppStorage storage;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('cloudy_storage_test');
    storage = AppStorage(temp);
  });

  tearDown(() => temp.deleteSync(recursive: true));

  FolderPair pair(String id) => FolderPair(
    id: id,
    name: 'Carpeta $id',
    localPath: '/storage/emulated/0/$id',
    remoteFolderId: 'remote-$id',
    remoteFolderPath: 'Mi unidad/$id',
    mode: SyncMode.uploadOnly,
    conflictPolicy: ConflictPolicy.preferNewest,
    excludePatterns: const ['*.tmp'],
  );

  test('guarda y recupera emparejamientos', () async {
    expect(await storage.loadPairs(), isEmpty);
    await storage.upsertPair(pair('a'));
    await storage.upsertPair(pair('b'));
    await storage.upsertPair(pair('a').copyWith(name: 'Renombrada'));

    final pairs = await storage.loadPairs();
    expect(pairs.map((p) => p.name), ['Renombrada', 'Carpeta b']);
    expect(pairs.first.mode, SyncMode.uploadOnly);
    expect(pairs.first.conflictPolicy, ConflictPolicy.preferNewest);
    expect(pairs.first.excludePatterns, ['*.tmp']);
  });

  test('actualiza sobre la versión en disco', () async {
    await storage.upsertPair(pair('a'));
    final syncedAt = DateTime(2026, 9, 29, 10);
    await storage.updatePair(
      'a',
      (p) => p.copyWith(
        lastSyncAt: syncedAt,
        lastOutcome: SyncOutcome.partial,
        lastMessage: '1 errores',
      ),
    );

    final stored = (await storage.loadPairs()).single;
    expect(stored.lastSyncAt, syncedAt);
    expect(stored.lastOutcome, SyncOutcome.partial);
    expect(stored.lastMessage, '1 errores');
  });

  test('al eliminar un emparejamiento se borra su estado', () async {
    await storage.upsertPair(pair('a'));
    await storage.saveState('a', {
      'x.txt': const FileSyncState(
        localModifiedMs: 1,
        localSize: 2,
        remoteId: 'r',
        remoteMd5: 'm',
        remoteModifiedMs: 3,
      ),
    });
    expect((await storage.loadState('a')).keys, ['x.txt']);

    await storage.removePair('a');

    expect(await storage.loadPairs(), isEmpty);
    expect(await storage.loadState('a'), isEmpty);
  });

  test('ajustes por defecto y guardados', () async {
    final defaults = await storage.loadSettings();
    expect(defaults.autoSync, isFalse);
    expect(defaults.wifiOnly, isTrue);

    await storage.saveSettings(
      const AppSettings(autoSync: true, intervalMinutes: 30),
    );
    final loaded = await storage.loadSettings();
    expect(loaded.autoSync, isTrue);
    expect(loaded.intervalMinutes, 30);
  });

  test('el registro guarda las entradas más recientes primero', () async {
    for (var i = 0; i < AppStorage.maxLogEntries + 5; i++) {
      await storage.appendLog(
        LogEntry(
          time: DateTime(2026, 1, 1).add(Duration(minutes: i)),
          level: LogLevel.info,
          title: 'Entrada $i',
          message: '',
        ),
      );
    }
    final log = await storage.loadLog();
    expect(log, hasLength(AppStorage.maxLogEntries));
    expect(log.first.title, 'Entrada ${AppStorage.maxLogEntries + 4}');
  });

  test('ignora archivos JSON corruptos', () async {
    await File('${temp.path}/folder_pairs.json').writeAsString('{roto');
    expect(await storage.loadPairs(), isEmpty);
  });
}
