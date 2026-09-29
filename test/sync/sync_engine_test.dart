import 'dart:io';

import 'package:cloudy/models/folder_pair.dart';
import 'package:cloudy/services/app_storage.dart';
import 'package:cloudy/sync/local_scanner.dart';
import 'package:cloudy/sync/sync_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_remote_drive.dart';

/// Carpeta local de prueba con fechas de modificación controladas, para que
/// cada escritura se detecte como un cambio.
class LocalFolder {
  LocalFolder(this.dir);

  final Directory dir;
  int _clock = 1600000000000;

  Future<void> write(String path, String content) async {
    final file = fileAt(dir.path, path);
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
    await file.setLastModified(
      DateTime.fromMillisecondsSinceEpoch(_clock += 5000),
    );
  }

  Future<void> delete(String path) async {
    final type = FileSystemEntity.typeSync(fileAt(dir.path, path).path);
    if (type == FileSystemEntityType.directory) {
      await Directory(fileAt(dir.path, path).path).delete(recursive: true);
    } else {
      await fileAt(dir.path, path).delete();
    }
  }

  bool dirExists(String path) =>
      Directory(fileAt(dir.path, path).path).existsSync();

  Map<String, String> files() => {
    for (final entity in dir.listSync(recursive: true))
      if (entity is File)
        toRelativePath(dir.path, entity.path): entity.readAsStringSync(),
  };
}

void main() {
  late Directory temp;
  late LocalFolder local;
  late FakeRemoteDrive remote;
  late AppStorage storage;
  late SyncEngine engine;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('cloudy_engine_test');
    local = LocalFolder(Directory('${temp.path}/local')..createSync());
    remote = FakeRemoteDrive();
    storage = AppStorage(Directory('${temp.path}/storage'));
    engine = SyncEngine(
      remote: remote,
      stateStore: storage,
      clock: () => DateTime(2026, 9, 29, 15, 30, 12),
    );
  });

  tearDown(() => temp.deleteSync(recursive: true));

  FolderPair pair({
    SyncMode mode = SyncMode.twoWay,
    ConflictPolicy policy = ConflictPolicy.keepBoth,
    bool propagateDeletions = true,
    List<String> exclude = const [],
    String? localPath,
  }) => FolderPair(
    id: 'p1',
    name: 'Prueba',
    localPath: localPath ?? local.dir.path,
    remoteFolderId: FakeRemoteDrive.rootId,
    remoteFolderPath: 'Mi unidad',
    mode: mode,
    conflictPolicy: policy,
    propagateDeletions: propagateDeletions,
    excludePatterns: exclude,
  );

  test('la primera sincronización bidireccional une ambos lados', () async {
    await local.write('a.txt', 'A');
    await local.write('sub/b.txt', 'B');
    remote.putFile('c.txt', 'C');
    remote.putFile('docs/d.txt', 'D');

    final report = await engine.run(pair());

    expect(report.fatalError, isNull);
    expect(report.uploaded, 2);
    expect(report.downloaded, 2);
    final expected = {
      'a.txt': 'A',
      'sub/b.txt': 'B',
      'c.txt': 'C',
      'docs/d.txt': 'D',
    };
    expect(local.files(), expected);
    expect(remote.files(), expected);
  });

  test('una segunda sincronización sin cambios no transfiere nada', () async {
    await local.write('a.txt', 'A');
    remote.putFile('b.txt', 'B');
    await engine.run(pair());
    final uploads = remote.uploadCount;
    final downloads = remote.downloadCount;

    final report = await engine.run(pair());

    expect(report.changes, 0);
    expect(report.summary, 'Todo al día');
    expect(remote.uploadCount, uploads);
    expect(remote.downloadCount, downloads);
  });

  test('archivos idénticos en ambos lados no se transfieren', () async {
    await local.write('same.txt', 'igual');
    remote.putFile('same.txt', 'igual');

    final report = await engine.run(pair());

    expect(report.changes, 0);
    expect(remote.uploadCount, 0);
    expect(remote.downloadCount, 0);
    expect((await storage.loadState('p1')).keys, ['same.txt']);
  });

  test('propaga modificaciones en ambos sentidos', () async {
    await local.write('a.txt', 'A1');
    remote.putFile('b.txt', 'B1');
    await engine.run(pair());

    await local.write('a.txt', 'A2 local');
    remote.putFile('b.txt', 'B2 remoto');
    final report = await engine.run(pair());

    expect(report.uploaded, 1);
    expect(report.downloaded, 1);
    expect(report.summary, '1 subido · 1 descargado');
    expect(remote.files()['a.txt'], 'A2 local');
    expect(local.files()['b.txt'], 'B2 remoto');
  });

  test('crea en Drive las carpetas intermedias necesarias', () async {
    await local.write('a/b/c/deep.txt', 'x');

    await engine.run(pair());

    expect(remote.files(), {'a/b/c/deep.txt': 'x'});
    expect(remote.folderExists('a/b'), isTrue);
  });

  test('un conflicto conserva ambas versiones', () async {
    await local.write('notas.txt', 'v1');
    await engine.run(pair());

    await local.write('notas.txt', 'versión local');
    remote.putFile('notas.txt', 'versión remota');
    final report = await engine.run(pair());

    expect(report.conflicts, 1);
    const conflictName = 'notas (conflicto 2026-09-29 153012).txt';
    final expected = {
      'notas.txt': 'versión remota',
      conflictName: 'versión local',
    };
    expect(local.files(), expected);
    expect(remote.files(), expected);

    // Y queda estable.
    expect((await engine.run(pair())).changes, 0);
  });

  test('conflicto con «gana el dispositivo»', () async {
    await local.write('a.txt', 'v1');
    await engine.run(pair());
    await local.write('a.txt', 'local');
    remote.putFile('a.txt', 'remoto');

    await engine.run(pair(policy: ConflictPolicy.preferLocal));

    expect(local.files(), {'a.txt': 'local'});
    expect(remote.files(), {'a.txt': 'local'});
  });

  test('borrar en local envía a la papelera de Drive', () async {
    await local.write('keep.txt', 'k');
    await local.write('old.txt', 'o');
    await engine.run(pair());

    await local.delete('old.txt');
    final report = await engine.run(pair());

    expect(report.deletedRemote, 1);
    expect(remote.files(), {'keep.txt': 'k'});
  });

  test('borrar una carpeta local elimina también la de Drive', () async {
    await local.write('keep.txt', 'k');
    await local.write('album/1.jpg', '1');
    await local.write('album/2.jpg', '2');
    await engine.run(pair());
    expect(remote.folderExists('album'), isTrue);

    await local.delete('album');
    await engine.run(pair());

    expect(remote.files(), {'keep.txt': 'k'});
    expect(remote.folderExists('album'), isFalse);
  });

  test('borrar en Drive borra el archivo y la carpeta vacía locales', () async {
    remote.putFile('keep.txt', 'k');
    remote.putFile('album/1.jpg', '1');
    await engine.run(pair());
    expect(local.dirExists('album'), isTrue);

    remote.deleteFile('album');
    final report = await engine.run(pair());

    expect(report.deletedLocal, 1);
    expect(local.files(), {'keep.txt': 'k'});
    expect(local.dirExists('album'), isFalse);
  });

  test('sin propagar eliminaciones se restaura lo borrado', () async {
    await local.write('keep.txt', 'k');
    await local.write('a.txt', 'A');
    await engine.run(pair(propagateDeletions: false));

    await local.delete('a.txt');
    await engine.run(pair(propagateDeletions: false));

    expect(local.files(), {'keep.txt': 'k', 'a.txt': 'A'});
    expect(remote.files(), {'keep.txt': 'k', 'a.txt': 'A'});
  });

  test('solo subir no descarga nada de Drive', () async {
    await local.write('mine.txt', 'm');
    remote.putFile('theirs.txt', 't');

    await engine.run(pair(mode: SyncMode.uploadOnly));

    expect(local.files(), {'mine.txt': 'm'});
    expect(remote.files(), {'mine.txt': 'm', 'theirs.txt': 't'});
  });

  test('solo descargar no sube nada a Drive', () async {
    await local.write('mine.txt', 'm');
    remote.putFile('theirs.txt', 't');

    await engine.run(pair(mode: SyncMode.downloadOnly));

    expect(local.files(), {'mine.txt': 'm', 'theirs.txt': 't'});
    expect(remote.files(), {'theirs.txt': 't'});
  });

  test('respeta exclusiones y archivos ocultos', () async {
    await local.write('a.txt', 'A');
    await local.write('b.tmp', 'tmp');
    await local.write('.oculto/x.txt', 'x');
    await local.write('cache/y.txt', 'y');
    remote.putFile('remoto.tmp', 'r');

    await engine.run(pair(exclude: ['*.tmp', 'cache']));

    expect(remote.files(), {'a.txt': 'A', 'remoto.tmp': 'r'});
    expect(local.files().containsKey('remoto.tmp'), isFalse);
  });

  test('no borra nada si la carpeta local aparece vacía', () async {
    await local.write('a.txt', 'A');
    await local.write('b.txt', 'B');
    await engine.run(pair());

    await local.delete('a.txt');
    await local.delete('b.txt');
    final report = await engine.run(pair());

    expect(report.fatalError, contains('vacía'));
    expect(remote.files(), {'a.txt': 'A', 'b.txt': 'B'});
  });

  test('no borra nada si la carpeta de Drive aparece vacía', () async {
    remote.putFile('a.txt', 'A');
    await engine.run(pair());

    remote.deleteFile('a.txt');
    final report = await engine.run(pair());

    expect(report.fatalError, contains('vacía'));
    expect(local.files(), {'a.txt': 'A'});
  });

  test('un error en un archivo no detiene el resto', () async {
    await local.write('bueno.txt', 'ok');
    await local.write('malo.txt', 'ko');
    remote.failingNames.add('malo.txt');

    final report = await engine.run(pair());

    expect(report.errors, hasLength(1));
    expect(report.errors.single, startsWith('malo.txt'));
    expect(remote.files(), {'bueno.txt': 'ok'});

    // Se reintenta en la siguiente sincronización.
    remote.failingNames.clear();
    final retry = await engine.run(pair());
    expect(retry.uploaded, 1);
    expect(remote.files(), {'bueno.txt': 'ok', 'malo.txt': 'ko'});
  });

  test('falla si la carpeta local no existe', () async {
    final report = await engine.run(pair(localPath: '${temp.path}/nope'));

    expect(report.fatalError, contains('no existe'));
  });

  test('se puede cancelar', () async {
    await local.write('a.txt', 'A');
    final cancellation = SyncCancellation()..cancel();

    final report = await engine.run(pair(), cancellation: cancellation);

    expect(report.cancelled, isTrue);
    expect(remote.files(), isEmpty);
  });
}
