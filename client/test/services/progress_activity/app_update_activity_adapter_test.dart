import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/progress_activity_cubit.dart';
import 'package:teampilot/models/progress_activity.dart';
import 'package:teampilot/services/notification/notification_recorder.dart';
import 'package:teampilot/services/progress_activity/app_update_activity_adapter.dart';

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
  group('AppUpdateActivityAdapter', () {
    late _FakeNotificationRecorder recorder;
    late ProgressActivityCubit cubit;
    late AppUpdateActivityAdapter adapter;

    setUp(() {
      recorder = _FakeNotificationRecorder();
      cubit = ProgressActivityCubit(historyRecorder: recorder);
      adapter = AppUpdateActivityAdapter(cubit: cubit);
    });

    tearDown(() {
      cubit.close();
    });

    test('startDownload tracks fraction and cancellable when supported', () {
      var cancelInvoked = false;
      final activityId = adapter.startDownload(
        title: 'Update v2.2.0',
        subtitle: 'Downloading update…',
        cancellable: true,
        onCancelRequested: () => cancelInvoked = true,
      );

      final activity = cubit.state.activities.single;
      expect(activity.id, activityId);
      expect(activity.kind, ProgressActivityKind.appUpdate);
      expect(activity.title, 'Update v2.2.0');
      expect(activity.subtitle, 'Downloading update…');
      expect(activity.fraction, 0);
      expect(activity.cancellable, isTrue);
      expect(activity.workspaceId, isNull);

      adapter.updateDownloadProgress(activityId, 0.42);
      expect(cubit.state.activities.single.fraction, 0.42);

      cubit.requestCancel(activityId);
      expect(cancelInvoked, isTrue);
    });

    test('startDownload is non-cancellable when cancel unsupported', () {
      final activityId = adapter.startDownload(
        title: 'Update v2.2.0',
        subtitle: 'Downloading update…',
      );

      final activity = cubit.state.activities.single;
      expect(activity.cancellable, isFalse);

      cubit.requestCancel(activityId);
      expect(cubit.state.activities, hasLength(1));
      expect(cubit.state.activities.single.phase, ProgressActivityPhase.running);
    });

    test('beginInstalling clears fraction and disables cancel', () {
      final activityId = adapter.startDownload(
        title: 'Update v2.2.0',
        subtitle: 'Downloading update…',
        cancellable: true,
        onCancelRequested: () {},
      );
      adapter.updateDownloadProgress(activityId, 0.9);

      adapter.beginInstalling(
        activityId,
        subtitle: 'Installing update…',
      );

      final activity = cubit.state.activities.single;
      expect(activity.fraction, isNull);
      expect(activity.subtitle, 'Installing update…');
      expect(activity.cancellable, isFalse);

      cubit.requestCancel(activityId);
      expect(cubit.state.activities.single.phase, ProgressActivityPhase.running);
    });

    test('completeSucceeded removes activity and records history', () {
      final activityId = adapter.startDownload(
        title: 'Update v2.2.0',
        subtitle: 'Downloading update…',
      );

      adapter.completeSucceeded(
        activityId,
        historyTitle: 'Update v2.2.0',
        historyMessage: 'Update installed',
      );

      expect(cubit.state.activities, isEmpty);
      expect(recorder.records, hasLength(1));
      expect(recorder.records.single.variant, TpToastVariant.success);
      expect(recorder.records.single.message, 'Update installed');
    });

    test('completeFailed records error outcome', () {
      final activityId = adapter.startDownload(
        title: 'Update v2.2.0',
        subtitle: 'Downloading update…',
      );

      adapter.completeFailed(
        activityId,
        historyTitle: 'Update v2.2.0',
        errorMessage: 'network down',
      );

      expect(cubit.state.activities, isEmpty);
      expect(recorder.records.single.variant, TpToastVariant.error);
      expect(recorder.records.single.message, 'network down');
    });

    test('completeCancelled records warning outcome', () {
      final activityId = adapter.startDownload(
        title: 'Update v2.2.0',
        subtitle: 'Downloading update…',
        cancellable: true,
        onCancelRequested: () {},
      );

      adapter.completeCancelled(
        activityId,
        historyTitle: 'Update v2.2.0',
        historyMessage: 'Download cancelled',
      );

      expect(cubit.state.activities, isEmpty);
      expect(recorder.records.single.variant, TpToastVariant.warning);
      expect(recorder.records.single.message, 'Download cancelled');
    });
  });
}
