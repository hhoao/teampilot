import 'chat_workbench_overlay.dart';

bool shouldShowSessionLaunchErrorBanner({
  required String? launchError,
  required bool sessionConnectInProgress,
}) {
  if (sessionConnectInProgress) return false;
  final text = launchError?.trim() ?? '';
  return text.isNotEmpty;
}

bool shouldShowTerminalSessionLaunchErrorBanner({
  required ChatWorkbenchOverlay overlay,
  required String? launchError,
  required bool sessionConnectInProgress,
}) {
  if (overlay != ChatWorkbenchOverlay.none) return false;
  return shouldShowSessionLaunchErrorBanner(
    launchError: launchError,
    sessionConnectInProgress: sessionConnectInProgress,
  );
}
