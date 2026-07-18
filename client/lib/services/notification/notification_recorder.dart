import 'package:shared_ui/shared_ui.dart';

/// Hook for [AppToast] to persist notifications without importing cubits.
abstract interface class NotificationRecorder {
  void record({
    required String message,
    required TpToastVariant variant,
    String title = '',
    String payload = '',
  });

  static NotificationRecorder? _current;

  static NotificationRecorder? get maybeCurrent => _current;

  static void install(NotificationRecorder? recorder) {
    _current = recorder;
  }
}
