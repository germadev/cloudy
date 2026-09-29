import 'package:cloudy/models/folder_pair.dart';
import 'package:cloudy/models/sync_state.dart';
import 'package:cloudy/sync/local_scanner.dart';
import 'package:cloudy/sync/remote_drive.dart';
import 'package:cloudy/sync/sync_planner.dart';
import 'package:flutter_test/flutter_test.dart';

LocalFile local({int mtime = 100, int size = 10, String? md5}) =>
    LocalFile(size: size, modifiedMs: mtime, md5: md5);

RemoteFile remote({String id = 'r1', String md5 = 'aaa', int mtime = 200}) =>
    RemoteFile(id: id, name: 'x', size: 10, md5: md5, modifiedMs: mtime);

/// Estado coherente con `local()` y `remote()` por defecto.
FileSyncState synced({String id = 'r1', String md5 = 'aaa'}) => FileSyncState(
  localModifiedMs: 100,
  localSize: 10,
  remoteId: id,
  remoteMd5: md5,
  remoteModifiedMs: 200,
);

List<SyncAction> plan({
  LocalFile? l,
  RemoteFile? r,
  FileSyncState? s,
  SyncMode mode = SyncMode.twoWay,
  ConflictPolicy policy = ConflictPolicy.keepBoth,
  bool propagateDeletions = true,
}) => planSync(
  local: {'f': ?l},
  remote: {'f': ?r},
  previous: {'f': ?s},
  mode: mode,
  conflictPolicy: policy,
  propagateDeletions: propagateDeletions,
);

SyncAction act(SyncActionType type) => SyncAction(type, 'f');

void main() {
  group('archivos nuevos', () {
    test('local nuevo se sube salvo en solo descargar', () {
      expect(plan(l: local()), [act(SyncActionType.upload)]);
      expect(plan(l: local(), mode: SyncMode.uploadOnly), [
        act(SyncActionType.upload),
      ]);
      expect(plan(l: local(), mode: SyncMode.downloadOnly), isEmpty);
    });

    test('remoto nuevo se descarga salvo en solo subir', () {
      expect(plan(r: remote()), [act(SyncActionType.download)]);
      expect(plan(r: remote(), mode: SyncMode.downloadOnly), [
        act(SyncActionType.download),
      ]);
      expect(plan(r: remote(), mode: SyncMode.uploadOnly), isEmpty);
    });

    test('mismo contenido en ambos lados solo registra el estado', () {
      expect(
        plan(
          l: local(md5: 'aaa'),
          r: remote(md5: 'aaa'),
        ),
        [act(SyncActionType.markSynced)],
      );
    });

    test('contenido distinto sin historial es un conflicto', () {
      expect(
        plan(
          l: local(md5: 'bbb'),
          r: remote(),
        ),
        [act(SyncActionType.keepBoth)],
      );
    });
  });

  group('cambios', () {
    test('sin cambios no hace nada', () {
      expect(plan(l: local(), r: remote(), s: synced()), isEmpty);
    });

    test('cambio local se sube', () {
      expect(plan(l: local(mtime: 300), r: remote(), s: synced()), [
        act(SyncActionType.updateRemote),
      ]);
    });

    test('cambio local se ignora en solo descargar', () {
      expect(
        plan(
          l: local(mtime: 300),
          r: remote(),
          s: synced(),
          mode: SyncMode.downloadOnly,
        ),
        isEmpty,
      );
    });

    test('cambio remoto se descarga', () {
      expect(
        plan(
          l: local(),
          r: remote(md5: 'ccc'),
          s: synced(),
        ),
        [act(SyncActionType.download)],
      );
    });

    test('archivo remoto reemplazado (otro id) cuenta como cambio', () {
      expect(
        plan(
          l: local(),
          r: remote(id: 'r2'),
          s: synced(),
        ),
        [act(SyncActionType.download)],
      );
    });

    test('cambio remoto se ignora en solo subir', () {
      expect(
        plan(
          l: local(),
          r: remote(md5: 'ccc'),
          s: synced(),
          mode: SyncMode.uploadOnly,
        ),
        isEmpty,
      );
    });

    test('cambio local con el mismo contenido que Drive no sube nada', () {
      expect(
        plan(
          l: local(mtime: 300, md5: 'aaa'),
          r: remote(),
          s: synced(),
        ),
        [act(SyncActionType.markSynced)],
      );
    });
  });

  group('conflictos', () {
    final l = local(mtime: 300, md5: 'bbb');
    final r = remote(md5: 'ccc', mtime: 250);

    test('se resuelven según la política', () {
      expect(plan(l: l, r: r, s: synced()), [act(SyncActionType.keepBoth)]);
      expect(
        plan(l: l, r: r, s: synced(), policy: ConflictPolicy.preferLocal),
        [act(SyncActionType.updateRemote)],
      );
      expect(
        plan(l: l, r: r, s: synced(), policy: ConflictPolicy.preferRemote),
        [act(SyncActionType.download)],
      );
      expect(
        plan(l: l, r: r, s: synced(), policy: ConflictPolicy.preferNewest),
        [act(SyncActionType.updateRemote)],
      );
      expect(
        plan(
          l: l,
          r: remote(md5: 'ccc', mtime: 400),
          s: synced(),
          policy: ConflictPolicy.preferNewest,
        ),
        [act(SyncActionType.download)],
      );
    });

    test('en modos unidireccionales gana el origen', () {
      expect(plan(l: l, r: r, s: synced(), mode: SyncMode.uploadOnly), [
        act(SyncActionType.updateRemote),
      ]);
      expect(plan(l: l, r: r, s: synced(), mode: SyncMode.downloadOnly), [
        act(SyncActionType.download),
      ]);
    });
  });

  group('eliminaciones', () {
    test('borrado en Drive borra el local', () {
      expect(plan(l: local(), s: synced()), [act(SyncActionType.deleteLocal)]);
    });

    test('borrado en Drive con cambio local vuelve a subir', () {
      expect(plan(l: local(mtime: 300), s: synced()), [
        act(SyncActionType.upload),
      ]);
    });

    test('borrado en Drive sin propagar vuelve a subir', () {
      expect(plan(l: local(), s: synced(), propagateDeletions: false), [
        act(SyncActionType.upload),
      ]);
    });

    test('borrado en Drive en solo subir restaura la copia', () {
      expect(plan(l: local(), s: synced(), mode: SyncMode.uploadOnly), [
        act(SyncActionType.upload),
      ]);
    });

    test('borrado en Drive en solo descargar', () {
      expect(plan(l: local(), s: synced(), mode: SyncMode.downloadOnly), [
        act(SyncActionType.deleteLocal),
      ]);
      expect(
        plan(
          l: local(),
          s: synced(),
          mode: SyncMode.downloadOnly,
          propagateDeletions: false,
        ),
        [act(SyncActionType.forget)],
      );
    });

    test('borrado local envía a la papelera de Drive', () {
      expect(plan(r: remote(), s: synced()), [act(SyncActionType.trashRemote)]);
      expect(plan(r: remote(), s: synced(), mode: SyncMode.uploadOnly), [
        act(SyncActionType.trashRemote),
      ]);
    });

    test('borrado local con cambio en Drive vuelve a descargar', () {
      expect(
        plan(
          r: remote(md5: 'ccc'),
          s: synced(),
        ),
        [act(SyncActionType.download)],
      );
    });

    test('borrado local sin propagar', () {
      expect(plan(r: remote(), s: synced(), propagateDeletions: false), [
        act(SyncActionType.download),
      ]);
      expect(
        plan(
          r: remote(),
          s: synced(),
          mode: SyncMode.uploadOnly,
          propagateDeletions: false,
        ),
        [act(SyncActionType.forget)],
      );
    });

    test('borrado local en solo descargar restaura desde Drive', () {
      expect(plan(r: remote(), s: synced(), mode: SyncMode.downloadOnly), [
        act(SyncActionType.download),
      ]);
    });

    test('borrado en ambos lados olvida el estado', () {
      expect(plan(s: synced()), [act(SyncActionType.forget)]);
    });
  });

  test('las acciones salen ordenadas por ruta', () {
    final actions = planSync(
      local: {'b': local(), 'a/z': local()},
      remote: {'c': remote()},
      previous: const {},
      mode: SyncMode.twoWay,
    );
    expect(actions.map((a) => a.path), ['a/z', 'b', 'c']);
  });
}
