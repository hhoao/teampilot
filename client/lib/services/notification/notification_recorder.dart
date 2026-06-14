import '../../theme/app_toast_theme.dart';

/// Hook for [AppToast] to persist notifications without importing cubits.
abstract interface class NotificationRecorder {
  void record({required String message, required AppToastVariant variant});

  static NotificationRecorder? _current;

  static NotificationRecorder? get maybeCurrent => _current;

  static void install(NotificationRecorder? recorder) {
    _current = recorder;
  }
}
