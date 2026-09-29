import 'dart:io';

import 'package:cloudy/sync/sync_lock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('cloudy_lock_test'));
  tearDown(() => temp.deleteSync(recursive: true));

  test('solo un poseedor a la vez', () async {
    final file = File('${temp.path}/sync.lock');
    final first = SyncLock(file);
    final second = SyncLock(file);

    expect(await first.tryAcquire(), isTrue);
    expect(await second.tryAcquire(), isFalse);

    await first.release();
    expect(await second.tryAcquire(), isTrue);
    await second.release();
  });

  test('un bloqueo abandonado caduca', () async {
    final file = File('${temp.path}/sync.lock')..createSync();
    file.setLastModifiedSync(
      DateTime.now().subtract(const Duration(minutes: 10)),
    );

    final lock = SyncLock(file);
    expect(await lock.tryAcquire(), isTrue);
    await lock.release();
    expect(file.existsSync(), isFalse);
  });
}
