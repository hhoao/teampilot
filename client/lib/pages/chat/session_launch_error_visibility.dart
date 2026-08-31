import 'chat_workbench_overlay.dart';

bool shouldShowSessionLaunchErrorBanner({
  required String? launchError,
  required bool sessionConnectInProgress,
}) {
  // Keep the failure card visible while Retry reconnects so the Retry button
  // can show a spinner. Ordinary connect/send has no launchError — no card.
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
