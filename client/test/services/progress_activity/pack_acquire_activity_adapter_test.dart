import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/progress_activity_cubit.dart';
import 'package:teampilot/models/progress_activity.dart';
import 'package:teampilot/services/notification/notification_recorder.dart';
import 'package:teampilot/services/progress_activity/pack_acquire_activity_adapter.dart';

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
  group('PackAcquireActivityAdapter', () {
    late _FakeNotificationRecorder recorder;
    late ProgressActivityCubit cubit;
    late PackAcquireActivityAdapter adapter;

    setUp(() {
      recorder = _FakeNotificationRecorder();
      cubit = ProgressActivityCubit(historyRecorder: recorder);
      adapter = PackAcquireActivityAdapter(cubit: cubit);
    });

    tearDown(() {
      cubit.close();
    });

    test('runTracked reports step progress and completes', () async {
      final result = await adapter.runTracked<String>(
        kind: ProgressActivityKind.packAcquire,
        title: 'Installing skill: lint',
        historyMessageFor: (_) => 'Installed lint',
        run: (onStep) async {
          onStep(subtitle: 'Downloading', completedSteps: 1, totalSteps: 3);
          onStep(subtitle: 'Registering', completedSteps: 3, totalSteps: 3);
          return 'skill-id';
        },
      );

      expect(result, 'skill-id');
      expect(cubit.state.activities, isEmpty);
      expect(recorder.records.single.variant, TpToastVariant.success);
      expect(recorder.records.single.message, 'Installed lint');
    });

    test('runTracked starts indeterminate without steps', () async {
      await adapter.runTracked<void>(
        kind: ProgressActivityKind.packAcquire,
        title: 'Installing plugin: git',
        run: (_) async {},
      );

      expect(cubit.state.activities, isEmpty);
      expect(recorder.records, hasLength(1));
    });

    test('runTracked completes failed on error', () async {
      await expectLater(
        adapter.runTracked<void>(
          kind: ProgressActivityKind.packAcquire,
          title: 'Installing extension: rtk',
          run: (_) async => throw StateError('install failed'),
        ),
        throwsA(isA<StateError>()),
      );

      expect(cubit.state.activities, isEmpty);
      expect(recorder.records.single.variant, TpToastVariant.error);
    });

    test('runTracked invokes cancel hook when cancellable', () async {
      var cancelHookInvoked = false;
      final future = adapter.runTracked<void>(
        kind: ProgressActivityKind.packAcquire,
        title: 'Installing skill: lint',
        cancellable: true,
        onCancelRequested: () => cancelHookInvoked = true,
        run: (_) async {},
      );

      final activityId = cubit.state.activities.single.id;
      cubit.requestCancel(activityId);
      await future;

      expect(cancelHookInvoked, isTrue);
    });

    test('runTracked uses custom outcome builder', () async {
      await adapter.runTracked<bool>(
        kind: ProgressActivityKind.packAcquire,
        title: 'Installing skill: lint',
        outcomeFor: (success) => success
            ? ProgressActivityPhase.succeeded
            : ProgressActivityPhase.failed,
        historyMessageFor: (success) => success ? 'ok' : 'failed',
        run: (_) async => false,
      );

      expect(recorder.records.single.variant, TpToastVariant.error);
      expect(recorder.records.single.message, 'failed');
    });
  });
}
