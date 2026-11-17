import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/progress_activity_cubit.dart';
import 'package:teampilot/models/install_job/install_cancel_policy.dart';
import 'package:teampilot/models/install_job/install_job_cancelled_exception.dart';
import 'package:teampilot/models/install_job/install_job_key.dart';
import 'package:teampilot/models/install_job/install_job_snapshot.dart';
import 'package:teampilot/models/install_job/install_job_spec.dart';
import 'package:teampilot/services/install/install_job_registry.dart';
import 'package:teampilot/services/install/job_log_store.dart';
import 'package:teampilot/services/notification/notification_recorder.dart';

import '../../support/in_memory_filesystem.dart';
import '../../support/post_frame_test_harness.dart';

class _FakeNotificationRecorder implements NotificationRecorder {
  final records =
      <
        ({String message, TpToastVariant variant, String title, String payload})
      >[];

  @override
  void record({
    required String message,
    required TpToastVariant variant,
    String title = '',
    String payload = '',
  }) {
    records.add((
      message: message,
      variant: variant,
      title: title,
      payload: payload,
    ));
  }
}

void main() {
  group('InstallJobRegistry', () {
    late _FakeNotificationRecorder recorder;
    late ProgressActivityCubit progressCubit;
    late InstallJobRegistry registry;

    setUp(() {
      recorder = _FakeNotificationRecorder();
      progressCubit = ProgressActivityCubit(historyRecorder: recorder);
      registry = InstallJobRegistry(progressCubit: progressCubit);
    });

    tearDown(() {
      registry.dispose();
      progressCubit.close();
    });

    test('enqueue coalesces identical keys', () async {
      var runCount = 0;
      final key = const InstallJobKey(
        kind: InstallJobKind.cliExecutable,
        target: 'claude',
      );
      final spec = InstallJobSpec<void>(
        key: key,
        title: 'Install Claude',
        cancelPolicy: InstallCancelPolicy.cooperative,
        run: (ctx) async {
          runCount++;
          await Future<void>.delayed(const Duration(milliseconds: 30));
        },
      );

      final first = registry.enqueue(spec);
      final second = registry.enqueue(spec);

      expect(registry.isRunning(key), isTrue);
      await Future.wait([first, second]);
      expect(runCount, 1);
      expect(registry.isRunning(key), isFalse);
    });

    test('onSucceeded runs even if only attachor awaits', () async {
      var succeeded = false;
      final gate = Completer<void>();
      final key = const InstallJobKey(
        kind: InstallJobKind.packAcquire,
        target: 'skill-1',
      );
      final spec = InstallJobSpec<String>(
        key: key,
        title: 'Acquire pack',
        cancelPolicy: InstallCancelPolicy.cooperative,
        run: (ctx) async {
          await gate.future;
          return 'done';
        },
        onSucceeded: (result) async {
          succeeded = true;
          expect(result, 'done');
        },
      );

      final leader = registry.enqueue(spec);
      unawaited(leader);
      final attachor = registry.enqueue(spec);

      gate.complete();
      await attachor;

      expect(succeeded, isTrue);
      expect(progressCubit.state.activities, isEmpty);
    });

    test('requestCancel cooperative sets cancelled outcome', () async {
      final key = const InstallJobKey(
        kind: InstallJobKind.hubClone,
        target: 'repo',
      );
      final spec = InstallJobSpec<void>(
        key: key,
        title: 'Clone hub',
        cancelPolicy: InstallCancelPolicy.cooperative,
        run: (ctx) async {
          while (!ctx.isCancelled) {
            await Future<void>.delayed(const Duration(milliseconds: 5));
          }
          throw InstallJobCancelledException(key);
        },
      );

      final snapshots = <InstallJobSnapshot>[];
      final subscription = registry.watch(key).listen(snapshots.add);

      final future = registry.enqueue(spec);
      await Future<void>.delayed(const Duration(milliseconds: 15));

      registry.requestCancel(key);

      await expectLater(future, throwsA(isA<InstallJobCancelledException>()));
      await waitUntil(
        () => snapshots.last.phase == InstallJobPhase.cancelled,
        timeout: const Duration(seconds: 5),
        step: const Duration(milliseconds: 10),
      );
      expect(registry.isRunning(key), isFalse);
      expect(progressCubit.state.activities, isEmpty);
      await subscription.cancel();
    });

    test('parallel different keys both run', () async {
      var countA = 0;
      var countB = 0;
      final keyA = const InstallJobKey(
        kind: InstallJobKind.cliExecutable,
        target: 'a',
      );
      final keyB = const InstallJobKey(
        kind: InstallJobKind.toolchain,
        target: 'b',
      );

      final futureA = registry.enqueue(
        InstallJobSpec<void>(
          key: keyA,
          title: 'Install A',
          cancelPolicy: InstallCancelPolicy.cooperative,
          run: (_) async {
            countA++;
          },
        ),
      );
      final futureB = registry.enqueue(
        InstallJobSpec<void>(
          key: keyB,
          title: 'Install B',
          cancelPolicy: InstallCancelPolicy.cooperative,
          run: (_) async {
            countB++;
          },
        ),
      );

      await Future.wait([futureA, futureB]);
      expect(countA, 1);
      expect(countB, 1);
      expect(registry.isRunning(keyA), isFalse);
      expect(registry.isRunning(keyB), isFalse);
    });
  });

  group('InstallJobRegistry logs', () {
    late _FakeNotificationRecorder recorder;
    late ProgressActivityCubit progressCubit;
    late InMemoryFilesystem fs;
    late JobLogStore logs;
    late InstallJobRegistry registry;

    setUp(() {
      recorder = _FakeNotificationRecorder();
      progressCubit = ProgressActivityCubit(historyRecorder: recorder);
      fs = InMemoryFilesystem();
      logs = JobLogStore(appDataRoot: '/tp', fs: fs);
      registry = InstallJobRegistry(progressCubit: progressCubit, logs: logs);
    });

    tearDown(() {
      registry.dispose();
      progressCubit.close();
    });

    const key = InstallJobKey(
      kind: InstallJobKind.cliExecutable,
      target: 'claude',
    );

    test('writes start, phase, output and ok lines, then closes', () async {
      final token = logs.tokenFor(key);
      final spec = InstallJobSpec<String>(
        key: key,
        title: 'Install Claude',
        cancelPolicy: InstallCancelPolicy.cooperative,
        run: (ctx) async {
          ctx.reportPhase('Installing CLI', detail: 'npm install');
          ctx.appendLog?.call('added 1 package');
          return 'done';
        },
      );

      await registry.enqueue(spec);

      expect(logs.isLive(token), isFalse);
      final lines = await logs.read(token);
      expect(lines.first, startsWith('[start]'));
      expect(lines, contains('[phase] Installing CLI — npm install'));
      expect(lines, contains('added 1 package'));
      expect(lines.last, startsWith('[ok]'));
      expect(recorder.records.single.payload, 'install-log:$token');
    });

    test('writes fail line with the error message', () async {
      final token = logs.tokenFor(key);
      final spec = InstallJobSpec<void>(
        key: key,
        title: 'Install Claude',
        cancelPolicy: InstallCancelPolicy.cooperative,
        run: (ctx) async => throw StateError('boom'),
      );

      await expectLater(registry.enqueue(spec), throwsStateError);

      final lines = await logs.read(token);
      expect(lines.last, '[fail] Bad state: boom');
      expect(recorder.records.single.payload, 'install-log:$token');
    });

    test('writes cancel line on cooperative cancel', () async {
      final token = logs.tokenFor(key);
      final spec = InstallJobSpec<void>(
        key: key,
        title: 'Install Claude',
        cancelPolicy: InstallCancelPolicy.cooperative,
        run: (ctx) async {
          while (!ctx.isCancelled) {
            await Future<void>.delayed(const Duration(milliseconds: 5));
          }
        },
      );

      final future = registry.enqueue(spec);
      final expectation = expectLater(future, throwsA(isA<Exception>()));
      registry.requestCancel(key);
      await expectation;

      final lines = await logs.read(token);
      expect(lines.last, '[cancel]');
    });
  });
}
