import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/progress_activity_cubit.dart';
import 'package:teampilot/models/progress_activity.dart';
import 'package:teampilot/services/notification/notification_recorder.dart';

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

ProgressActivity _activity({
  required String id,
  DateTime? createdAt,
  String? workspaceId,
  bool cancellable = false,
  ProgressActivityPhase phase = ProgressActivityPhase.running,
  String title = 'Title',
}) {
  final at = createdAt ?? DateTime(2026, 7, 30, 12);
  return ProgressActivity(
    id: id,
    kind: ProgressActivityKind.fileTreeImport,
    title: title,
    phase: phase,
    workspaceId: workspaceId,
    cancellable: cancellable,
    createdAt: at,
    updatedAt: at,
  );
}

ProgressActivityCubit _cubit(_FakeNotificationRecorder recorder) {
  return ProgressActivityCubit(historyRecorder: recorder);
}

void main() {
  group('ProgressActivityCubit', () {
    test('orders activities FIFO by createdAt', () {
      final recorder = _FakeNotificationRecorder();
      final cubit = _cubit(recorder);
      addTearDown(cubit.close);

      cubit.start(
        _activity(id: 'b', createdAt: DateTime(2026, 7, 30, 12, 1)),
      );
      cubit.start(
        _activity(id: 'a', createdAt: DateTime(2026, 7, 30, 12, 0)),
      );

      expect(cubit.state.activities.map((a) => a.id), ['a', 'b']);
    });

    test('start with same id replaces in place', () {
      final recorder = _FakeNotificationRecorder();
      final cubit = _cubit(recorder);
      addTearDown(cubit.close);

      cubit.start(
        _activity(
          id: 'a',
          createdAt: DateTime(2026, 7, 30, 12, 0),
          title: 'First',
        ),
      );
      cubit.start(
        _activity(
          id: 'b',
          createdAt: DateTime(2026, 7, 30, 12, 1),
          title: 'Second',
        ),
      );
      cubit.start(
        _activity(
          id: 'a',
          createdAt: DateTime(2026, 7, 30, 12, 9),
          title: 'Updated',
        ),
      );

      expect(cubit.state.activities.map((a) => a.id), ['a', 'b']);
      expect(cubit.state.activities.first.title, 'Updated');
      expect(
        cubit.state.activities.first.createdAt,
        DateTime(2026, 7, 30, 12, 0),
      );
    });

    test('requestCancel sets cancelling and invokes hook once', () {
      final recorder = _FakeNotificationRecorder();
      final cubit = _cubit(recorder);
      addTearDown(cubit.close);
      var cancelCount = 0;

      cubit.start(
        _activity(id: 'a', cancellable: true),
        onCancelRequested: () => cancelCount++,
      );

      cubit.requestCancel('a');
      cubit.requestCancel('a');

      expect(cubit.state.activities.single.phase, ProgressActivityPhase.cancelling);
      expect(cancelCount, 1);
    });

    test(
      'requestCancel without hook asserts in debug for cancellable activity',
      () {
        final recorder = _FakeNotificationRecorder();
        final cubit = _cubit(recorder);
        addTearDown(cubit.close);

        cubit.start(_activity(id: 'a', cancellable: true));

        expect(() => cubit.requestCancel('a'), throwsAssertionError);
      },
      skip: !kDebugMode ? 'assert only in debug' : false,
    );

    test('complete removes activity and records history variant', () {
      final recorder = _FakeNotificationRecorder();
      final cubit = _cubit(recorder);
      addTearDown(cubit.close);

      cubit.start(_activity(id: 'ok', title: 'Import'));
      cubit.complete(
        'ok',
        outcome: ProgressActivityPhase.succeeded,
        historyMessage: 'Done',
      );

      expect(cubit.state.activities, isEmpty);
      expect(recorder.records.single.variant, TpToastVariant.success);
      expect(recorder.records.single.message, 'Done');
      expect(recorder.records.single.title, 'Import');
    });

    test('complete maps failed and cancelled outcomes', () {
      final recorder = _FakeNotificationRecorder();
      final cubit = _cubit(recorder);
      addTearDown(cubit.close);

      cubit.start(_activity(id: 'fail'));
      cubit.complete(
        'fail',
        outcome: ProgressActivityPhase.failed,
        historyMessage: 'Boom',
      );

      cubit.start(_activity(id: 'cancel'));
      cubit.complete(
        'cancel',
        outcome: ProgressActivityPhase.cancelled,
        historyMessage: 'Stopped',
      );

      expect(recorder.records[0].variant, TpToastVariant.error);
      expect(recorder.records[1].variant, TpToastVariant.warning);
    });

    test('setDetailOpen toggles flag without cancelling', () {
      final recorder = _FakeNotificationRecorder();
      final cubit = _cubit(recorder);
      addTearDown(cubit.close);
      var cancelCount = 0;

      cubit.start(
        _activity(id: 'a', cancellable: true),
        onCancelRequested: () => cancelCount++,
      );

      cubit.setDetailOpen('a', true);
      cubit.setDetailOpen('a', false);

      expect(cubit.state.activities.single.detailOpen, isFalse);
      expect(cubit.state.activities.single.phase, ProgressActivityPhase.running);
      expect(cancelCount, 0);
    });

    test('forWorkspace includes global and matching workspace activities', () {
      final recorder = _FakeNotificationRecorder();
      final cubit = _cubit(recorder);
      addTearDown(cubit.close);

      cubit.start(_activity(id: 'global', workspaceId: null));
      cubit.start(_activity(id: 'w1', workspaceId: 'ws-1'));
      cubit.start(_activity(id: 'w2', workspaceId: 'ws-2'));

      final scoped = cubit.state.forWorkspace('ws-1');

      expect(scoped.map((a) => a.id), ['global', 'w1']);
    });

    test('update patches progress fields', () {
      final recorder = _FakeNotificationRecorder();
      final cubit = _cubit(recorder);
      addTearDown(cubit.close);

      cubit.start(_activity(id: 'a'));
      cubit.update('a', fraction: 0.5, completedItems: 2, totalItems: 4);

      final activity = cubit.state.activities.single;
      expect(activity.fraction, 0.5);
      expect(activity.completedItems, 2);
      expect(activity.totalItems, 4);
    });
  });
}
