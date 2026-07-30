import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/progress_activity_cubit.dart';
import 'package:teampilot/models/progress_activity.dart';
import 'package:teampilot/services/notification/notification_recorder.dart';
import 'package:teampilot/services/progress_activity/hub_clone_activity_adapter.dart';
import 'package:teampilot/services/team/team_clone_service.dart';

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

void main() {
  group('HubCloneActivityAdapter', () {
    late _FakeNotificationRecorder recorder;
    late ProgressActivityCubit cubit;
    late HubCloneActivityAdapter adapter;

    setUp(() {
      recorder = _FakeNotificationRecorder();
      cubit = ProgressActivityCubit(historyRecorder: recorder);
      adapter = HubCloneActivityAdapter(cubit: cubit);
    });

    tearDown(() {
      cubit.close();
    });

    test('runTracked reports CloneProgress items and completes', () async {
      final progresses = <CloneProgress>[];

      final result = await adapter.runTracked<CloneResult>(
        title: 'Clone Team Alpha',
        historyMessageFor: (_) => 'Cloned Team Alpha',
        run: (onProgress) async {
          onProgress(const CloneProgress('skill-a', 1, 2));
          onProgress(const CloneProgress('skill-b', 2, 2));
          return const CloneResult(
            teamId: 'team-1',
            installed: CloneDepInstallSummary(skillIds: ['skill-a']),
            failedDeps: const [],
          );
        },
      );

      expect(result.teamId, 'team-1');
      expect(cubit.state.activities, isEmpty);
      expect(recorder.records, hasLength(1));
      expect(recorder.records.single.variant, TpToastVariant.success);
      expect(recorder.records.single.message, 'Cloned Team Alpha');

      expect(progresses, isEmpty);
    });

    test('runTracked updates fraction from CloneProgress', () async {
      late String activityId;

      final future = adapter.runTracked<void>(
        title: 'Clone Team Alpha',
        run: (onProgress) async {
          activityId = cubit.state.activities.single.id;
          onProgress(const CloneProgress('dep-a', 1, 4));
          expect(cubit.state.activities.single.fraction, 0.25);
          expect(cubit.state.activities.single.completedItems, 1);
          expect(cubit.state.activities.single.totalItems, 4);
          expect(cubit.state.activities.single.subtitle, 'dep-a');
        },
      );

      await future;
      expect(activityId, isNotEmpty);
    });

    test('runTracked is non-cancellable', () async {
      final future = adapter.runTracked<void>(
        title: 'Clone Team Alpha',
        run: (_) async {},
      );

      final activityId = cubit.state.activities.single.id;
      cubit.requestCancel(activityId);

      await future;
      expect(cubit.state.activities, isEmpty);
    });

    test('runTracked completes failed on error', () async {
      await expectLater(
        adapter.runTracked<void>(
          title: 'Clone Team Alpha',
          run: (_) async => throw CloneException('team creation failed'),
        ),
        throwsA(isA<CloneException>()),
      );

      expect(cubit.state.activities, isEmpty);
      expect(recorder.records.single.variant, TpToastVariant.error);
      expect(
        recorder.records.single.message,
        contains('team creation failed'),
      );
    });

    test('runTracked uses custom outcome builder', () async {
      await adapter.runTracked<CloneResult>(
        title: 'Clone Team Alpha',
        outcomeFor: (result) => result.hasFailures
            ? ProgressActivityPhase.failed
            : ProgressActivityPhase.succeeded,
        historyMessageFor: (_) => 'partial',
        run: (_) async => const CloneResult(
          teamId: 'team-1',
          installed: const CloneDepInstallSummary(),
          failedDeps: [DependencyFailure(DependencyKind.skill, 'missing')],
        ),
      );

      expect(recorder.records.single.variant, TpToastVariant.error);
    });
  });
}
