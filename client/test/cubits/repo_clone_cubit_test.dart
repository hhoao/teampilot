import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/progress_activity_cubit.dart';
import 'package:teampilot/cubits/repo_clone_cubit.dart';
import 'package:teampilot/models/progress_activity.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/notification/notification_recorder.dart';
import 'package:teampilot/services/workspace/repo_clone_service.dart';

import '../support/in_memory_filesystem.dart';

class _FakeNotificationRecorder implements NotificationRecorder {
  final records = <({String message, TpToastVariant variant, String title})>[];

  @override
  void record({
    required String message,
    required TpToastVariant variant,
    String title = '',
    String payload = '',
  }) {
    records.add((message: message, variant: variant, title: title));
  }
}

class _FakeService implements RepoCloneGateway {
  _FakeService();

  RepoCloneRequest? lastRequest;
  void Function(RepoCloneProgress progress)? onProgress;
  bool Function()? isCancelled;

  /// Optional gate that clone() awaits before returning the result.
  Completer<void>? gate;

  RepoCloneResult result = const RepoCloneResult(
    outcome: RepoCloneOutcome.succeeded,
    destPath: '/src/r',
  );

  @override
  Future<RepoCloneResult> clone(
    RepoCloneRequest request, {
    required void Function(RepoCloneProgress progress) onProgress,
    required bool Function() isCancelled,
  }) async {
    lastRequest = request;
    this.onProgress = onProgress;
    this.isCancelled = isCancelled;
    final pendingGate = gate;
    if (pendingGate != null) {
      await pendingGate.future;
    }
    return result;
  }
}

class _ThrowingService implements RepoCloneGateway {
  @override
  Future<RepoCloneResult> clone(
    RepoCloneRequest request, {
    required void Function(RepoCloneProgress progress) onProgress,
    required bool Function() isCancelled,
  }) async {
    throw StateError('boom');
  }
}

(ProgressActivityCubit, _FakeNotificationRecorder) _progress() {
  final recorder = _FakeNotificationRecorder();
  final cubit = ProgressActivityCubit(historyRecorder: recorder);
  addTearDown(cubit.close);
  return (cubit, recorder);
}

RepoCloneCubit _cubit(
  ProgressActivityCubit progress,
  RepoCloneGateway service, {
  String Function()? uuid,
  Future<Filesystem> Function(String targetId)? cleanupFs,
}) {
  final cubit = RepoCloneCubit(
    progressActivityCubit: progress,
    service: service,
    uuid: uuid ?? () => 'id-1',
    cleanupFs: cleanupFs,
  );
  addTearDown(cubit.close);
  return cubit;
}

RepoCloneRequest _request() {
  return const RepoCloneRequest(
    url: 'https://github.com/o/r.git',
    targetId: 'local',
    parentDir: '/src',
    dirName: 'r',
  );
}

Future<void> _pumpUntil(
  bool Function() condition, {
  int maxIterations = 100,
}) async {
  for (var i = 0; i < maxIterations && !condition(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('RepoCloneCubit', () {
    test('startClone registers a cancellable repoClone activity', () async {
      final (progress, _) = _progress();
      final fake = _FakeService();
      final cubit = _cubit(progress, fake);

      cubit.startClone(_request());

      expect(cubit.state.tasks.single.phase, RepoCloneTaskPhase.cloning);
      expect(cubit.state.tasks.single.id, 'id-1');
      expect(cubit.state.tasks.single.url, 'https://github.com/o/r.git');
      expect(cubit.state.tasks.single.targetId, 'local');
      expect(cubit.state.tasks.single.dirName, 'r');
      final activity = progress.state.activities.single;
      expect(activity.kind, ProgressActivityKind.repoClone);
      expect(activity.id, 'id-1');
      expect(activity.cancellable, isTrue);
      expect(activity.phase, ProgressActivityPhase.running);
      expect(activity.title, 'r');
    });

    test(
      'succeeded clone lands in pendingChoice and completes the activity',
      () async {
        final (progress, recorder) = _progress();
        final fake = _FakeService();
        final cubit = _cubit(progress, fake);

        cubit.startClone(_request());

        await _pumpUntil(
          () => cubit.state.tasks.single.phase == RepoCloneTaskPhase.succeeded,
        );

        expect(cubit.state.pendingChoice.single.id, 'id-1');
        expect(cubit.state.tasks.single.phase, RepoCloneTaskPhase.succeeded);
        // destPath from the result replaces the provisional join.
        expect(cubit.state.tasks.single.destPath, '/src/r');
        expect(progress.state.activities, isEmpty);
        expect(recorder.records.single.variant, TpToastVariant.success);
        expect(recorder.records.single.title, 'Cloned r');
      },
    );

    test('failed clone sets errorDetail and completes failed', () async {
      final (progress, recorder) = _progress();
      final fake = _FakeService();
      fake.result = const RepoCloneResult(
        outcome: RepoCloneOutcome.failed,
        destPath: '/src/r',
        errorDetail: 'fatal: could not read Username',
      );
      final cubit = _cubit(progress, fake);

      cubit.startClone(_request());

      await _pumpUntil(
        () => cubit.state.tasks.single.phase == RepoCloneTaskPhase.failed,
      );

      expect(
        cubit.state.tasks.single.errorDetail,
        'fatal: could not read Username',
      );
      expect(cubit.state.pendingChoice, isEmpty);
      expect(progress.state.activities, isEmpty);
      expect(recorder.records.single.variant, TpToastVariant.error);
    });

    test('dest-exists marker is passed through in errorDetail', () async {
      final (progress, _) = _progress();
      final fake = _FakeService();
      fake.result = const RepoCloneResult(
        outcome: RepoCloneOutcome.failed,
        destPath: '/src/r',
        errorDetail: 'dest-exists',
      );
      final cubit = _cubit(progress, fake);

      cubit.startClone(_request());

      await _pumpUntil(
        () => cubit.state.tasks.single.phase == RepoCloneTaskPhase.failed,
      );
      expect(cubit.state.tasks.single.errorDetail, 'dest-exists');
      expect(cubit.state.pendingChoice, isEmpty);
    });

    test('dismissChoice removes only from pendingChoice', () async {
      final (progress, _) = _progress();
      final fake = _FakeService();
      final cubit = _cubit(progress, fake);

      cubit.startClone(_request());
      await _pumpUntil(
        () => cubit.state.tasks.single.phase == RepoCloneTaskPhase.succeeded,
      );

      cubit.dismissChoice('id-1');

      expect(cubit.state.pendingChoice, isEmpty);
      expect(cubit.state.tasks, isNotEmpty);
      expect(cubit.state.tasks.single.id, 'id-1');
    });

    test('progress events forward to the activity', () async {
      final (progress, _) = _progress();
      final fake = _FakeService();
      final cubit = _cubit(progress, fake);

      cubit.startClone(_request());

      fake.onProgress!(
        const RepoCloneProgress(fraction: 0.45, subtitle: 'Receiving...'),
      );

      final activity = progress.state.activities.single;
      expect(activity.fraction, 0.45);
      expect(activity.subtitle, 'Receiving...');
    });

    test('requestCancel flips the flag the service polls', () async {
      final (progress, _) = _progress();
      final fake = _FakeService()..gate = Completer<void>();
      final cubit = _cubit(progress, fake);

      cubit.startClone(_request());
      // Clone is parked on the gate; exercise the cancel path now.
      expect(fake.isCancelled!(), isFalse);
      progress.requestCancel('id-1');
      expect(fake.isCancelled!(), isTrue);

      fake.gate!.complete();
      await _pumpUntil(
        () => cubit.state.tasks.single.phase == RepoCloneTaskPhase.succeeded,
      );
      expect(fake.lastRequest?.dirName, 'r');
    });

    test(
      'cancelled outcome maps to cancelled phase and warning record',
      () async {
        final (progress, recorder) = _progress();
        final fake = _FakeService();
        fake.result = const RepoCloneResult(
          outcome: RepoCloneOutcome.cancelled,
          destPath: '/src/r',
        );
        final cubit = _cubit(progress, fake);

        cubit.startClone(_request());

        await _pumpUntil(
          () => cubit.state.tasks.single.phase == RepoCloneTaskPhase.cancelled,
        );

        expect(cubit.state.pendingChoice, isEmpty);
        expect(progress.state.activities, isEmpty);
        expect(recorder.records.single.variant, TpToastVariant.warning);
      },
    );

    test('taskById finds tasks across the lifecycle', () async {
      final (progress, _) = _progress();
      final cubit = _cubit(progress, _FakeService());

      expect(cubit.taskById('id-1'), isNull);

      cubit.startClone(_request());
      expect(cubit.taskById('id-1')?.phase, RepoCloneTaskPhase.cloning);

      await _pumpUntil(
        () => cubit.state.tasks.single.phase == RepoCloneTaskPhase.succeeded,
      );
      expect(cubit.taskById('id-1')?.phase, RepoCloneTaskPhase.succeeded);
    });

    test('failed clone runs best-effort second-pass cleanup', () async {
      final (progress, _) = _progress();
      final fake = _FakeService();
      fake.result = const RepoCloneResult(
        outcome: RepoCloneOutcome.failed,
        destPath: '/src/r',
        errorDetail: 'fatal: remote error',
      );
      final fs = InMemoryFilesystem();
      await fs.ensureDir('/src/r');
      final cubit = _cubit(progress, fake, cleanupFs: (targetId) async => fs);

      cubit.startClone(_request());
      await _pumpUntil(
        () => cubit.state.tasks.single.phase == RepoCloneTaskPhase.failed,
      );

      final stat = await fs.stat('/src/r');
      expect(stat.kind, FsEntityKind.notFound);
    });

    test('dest-exists failure never triggers second-pass cleanup', () async {
      final (progress, _) = _progress();
      final fake = _FakeService();
      fake.result = const RepoCloneResult(
        outcome: RepoCloneOutcome.failed,
        destPath: '/src/r',
        errorDetail: 'dest-exists',
      );
      final fs = InMemoryFilesystem();
      await fs.ensureDir('/src/r');
      final cubit = _cubit(progress, fake, cleanupFs: (targetId) async => fs);

      cubit.startClone(_request());
      await _pumpUntil(
        () => cubit.state.tasks.single.phase == RepoCloneTaskPhase.failed,
      );

      final stat = await fs.stat('/src/r');
      expect(stat.kind, FsEntityKind.directory);
    });

    test('cancelled clone runs best-effort second-pass cleanup', () async {
      final (progress, _) = _progress();
      final fake = _FakeService();
      fake.result = const RepoCloneResult(
        outcome: RepoCloneOutcome.cancelled,
        destPath: '/src/r',
      );
      final fs = InMemoryFilesystem();
      await fs.ensureDir('/src/r');
      final cubit = _cubit(progress, fake, cleanupFs: (targetId) async => fs);

      cubit.startClone(_request());
      await _pumpUntil(
        () => cubit.state.tasks.single.phase == RepoCloneTaskPhase.cancelled,
      );

      final stat = await fs.stat('/src/r');
      expect(stat.kind, FsEntityKind.notFound);
    });

    test('succeeded clone never runs second-pass cleanup', () async {
      final (progress, _) = _progress();
      final fake = _FakeService();
      final fs = InMemoryFilesystem();
      await fs.ensureDir('/src/r');
      final cubit = _cubit(progress, fake, cleanupFs: (targetId) async => fs);

      cubit.startClone(_request());
      await _pumpUntil(
        () => cubit.state.tasks.single.phase == RepoCloneTaskPhase.succeeded,
      );

      final stat = await fs.stat('/src/r');
      expect(stat.kind, FsEntityKind.directory);
    });

    test('clone errors land in state as a failed task', () async {
      final (progress, recorder) = _progress();
      final cubit = _cubit(progress, _ThrowingService());

      cubit.startClone(_request());

      await _pumpUntil(
        () => cubit.state.tasks.single.phase == RepoCloneTaskPhase.failed,
      );

      expect(cubit.state.tasks.single.errorDetail, contains('boom'));
      expect(recorder.records.single.variant, TpToastVariant.error);
    });

    test(
      'closing the cubit mid-clone does not throw and still completes the activity',
      () async {
        final (progress, recorder) = _progress();
        final fake = _FakeService()..gate = Completer<void>();
        final cubit = RepoCloneCubit(
          progressActivityCubit: progress,
          service: fake,
          uuid: () => 'id-1',
        );

        cubit.startClone(_request());
        await cubit.close();

        fake.gate!.complete();
        await _pumpUntil(() => progress.state.activities.isEmpty);

        // No unhandled zone error (the test itself would fail) and the
        // app-scoped activity finished: removed + recorded in history.
        expect(progress.state.activities, isEmpty);
        expect(recorder.records.single.title, 'Cloned r');
        expect(recorder.records.single.message, '/src/r');
        expect(recorder.records.single.variant, TpToastVariant.success);
      },
    );

    test(
      'raced already-exists failure never triggers second-pass cleanup',
      () async {
        final (progress, _) = _progress();
        final fake = _FakeService();
        fake.result = const RepoCloneResult(
          outcome: RepoCloneOutcome.failed,
          destPath: '/src/r',
          errorDetail:
              "fatal: destination path '/src/r' already exists and is not an "
              'empty directory.',
        );
        final fs = InMemoryFilesystem();
        await fs.ensureDir('/src/r');
        final cubit = _cubit(progress, fake, cleanupFs: (targetId) async => fs);

        cubit.startClone(_request());
        await _pumpUntil(
          () => cubit.state.tasks.single.phase == RepoCloneTaskPhase.failed,
        );

        final stat = await fs.stat('/src/r');
        expect(stat.kind, FsEntityKind.directory);
      },
    );

    test('closing mid-clone makes the gateway see isCancelled true', () async {
      final (progress, _) = _progress();
      final fake = _FakeService()..gate = Completer<void>();
      final cubit = RepoCloneCubit(
        progressActivityCubit: progress,
        service: fake,
        uuid: () => 'id-1',
      );

      cubit.startClone(_request());
      expect(fake.isCancelled!(), isFalse);
      await cubit.close();
      expect(fake.isCancelled!(), isTrue);

      fake.gate!.complete();
      await _pumpUntil(() => progress.state.activities.isEmpty);
    });
  });
}
