import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/progress_activity_cubit.dart';
import 'package:teampilot/services/notification/notification_recorder.dart';

class _NoopRecorder implements NotificationRecorder {
  @override
  void record({
    required String message,
    required TpToastVariant variant,
    String title = '',
    String payload = '',
  }) {}
}

class TestProgressCubit extends ProgressActivityCubit {
  TestProgressCubit() : super(historyRecorder: _NoopRecorder());
}
