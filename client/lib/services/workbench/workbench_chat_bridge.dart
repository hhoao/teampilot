import '../../cubits/workbench/workbench_cubit.dart';

/// Single domain ↔ bar handshake. Feeds the bar on session open; later tasks
/// add close teardown and the foreground-session mirror here.
class WorkbenchChatBridge {
  WorkbenchChatBridge({required WorkbenchCubit workbench})
    : _workbench = workbench;

  final WorkbenchCubit _workbench;

  /// Session domain staged a new/reused session tab; surface it in the bar.
  void onSessionTabOpened(
    String workspaceId,
    String sessionId, {
    bool preview = false,
    bool activate = true,
  }) {
    _workbench.openSession(
      workspaceId,
      sessionId,
      preview: preview,
      activate: activate,
    );
  }
}
