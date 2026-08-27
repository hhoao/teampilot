import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/run_tests.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('run_tests_lock');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('serializes concurrent bodies until the holder releases', () async {
    final lockPath = '${tempDir.path}/run_tests.lock';
    final releaseFirst = Completer<void>();
    final events = <String>[];

    final first = withTestSuiteLock(lockPath, () async {
      events.add('first:start');
      await releaseFirst.future;
      events.add('first:end');
    });

    while (!events.contains('first:start')) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    final second = withTestSuiteLock(
      lockPath,
      () async {
        events.add('second:start');
      },
      onWaitStart: () {},
    );

    // The second body must not start while the first holds the lock.
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(events, isNot(contains('second:start')));

    releaseFirst.complete();
    await first;
    await second.timeout(const Duration(seconds: 10));
    expect(events, ['first:start', 'first:end', 'second:start']);
  });

  test('reports contention through onWaitStart', () async {
    final lockPath = '${tempDir.path}/run_tests.lock';
    final releaseFirst = Completer<void>();
    var waitReported = false;

    final first = withTestSuiteLock(lockPath, () => releaseFirst.future);

    final second = withTestSuiteLock(
      lockPath,
      () async {},
      onWaitStart: () => waitReported = true,
    );

    while (!waitReported) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(waitReported, isTrue);

    releaseFirst.complete();
    await first;
    await second.timeout(const Duration(seconds: 10));
  });

  test('releases the lock when the body throws', () async {
    final lockPath = '${tempDir.path}/run_tests.lock';

    await expectLater(
      withTestSuiteLock<void>(lockPath, () async {
        throw StateError('boom');
      }),
      throwsStateError,
    );

    final events = <String>[];
    await withTestSuiteLock(lockPath, () async {
      events.add('acquired-after-failure');
    });
    expect(events, ['acquired-after-failure']);
  });
}
