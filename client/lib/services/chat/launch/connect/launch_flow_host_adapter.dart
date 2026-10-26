import 'launch_flow.dart';

/// Maps launch-owned flow events onto connect UI + tab pending sets.
///
/// Lives at the composition boundary so [SessionConnectScheduler] does not
/// import ChatTab, ChatCubit, or ChatState.
final class LaunchFlowHostAdapter implements LaunchFlowListener {
  LaunchFlowHostAdapter({
    required this.beginSessionConnect,
    required this.isSessionConnecting,
    required this.finishSessionConnect,
    required this.pendingMembersForSession,
  });

  final void Function(String sessionId) beginSessionConnect;
  final bool Function(String sessionId) isSessionConnecting;
  final void Function(String sessionId) finishSessionConnect;
  final Set<String>? Function(String sessionId) pendingMembersForSession;

  @override
  void onLaunchFlow(LaunchFlowEvent event) {
    switch (event.phase) {
      case LaunchFlowPhase.queued:
        pendingMembersForSession(event.sessionId)?.add(event.memberId);
        // Deferred preparation (connectShell: false) is not a connect: it must
        // not flip the pod phase, or a history-only open shows the sidebar
        // "running" spinner and can suppress a real connect's own state.
        if (event.showsConnectUi) beginSessionConnect(event.sessionId);
      case LaunchFlowPhase.settled:
        pendingMembersForSession(event.sessionId)?.remove(event.memberId);
        if (event.showsConnectUi && isSessionConnecting(event.sessionId)) {
          finishSessionConnect(event.sessionId);
        }
    }
  }
}
