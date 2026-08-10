import 'dart:async';

import '../../cubits/chat/session_launch_host.dart';
import '../../cubits/chat_cubit.dart';
import '../../cubits/workbench/workbench_cubit.dart';
import '../../cubits/workbench/workbench_domain_port.dart';
import '../../cubits/workbench/workbench_tab.dart';

/// Domain ↔ bar handshake. Feeds the bar on session open, routes domain-driven
/// closes and landing through the bar, and mirrors the bar's center-active
/// session back into [ChatState.activeSessionId] / `selectedMemberId`.
class WorkbenchChatBridge implements WorkbenchDomainPort, ChatWorkbenchPort {
  WorkbenchChatBridge({
    required WorkbenchCubit workbench,
    required ChatCubit chat,
  }) : _workbench = workbench,
       _chat = chat {
    // Single writer for the foreground-session mirror: the bar's center active
    // id. Syncs after any open/close/activate/landing change.
    _workbenchSub = _workbench.stream.listen((_) => _syncForeground());
  }

  final WorkbenchCubit _workbench;
  final ChatCubit _chat;
  StreamSubscription<WorkbenchState>? _workbenchSub;

  /// Cancels the foreground-sync subscription. The bridge is app-lifetime in
  /// practice, so this is only invoked on teardown.
  void dispose() {
    _workbenchSub?.cancel();
    _workbenchSub = null;
  }

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

  // ===== ChatWorkbenchPort (domain → bar) =====

  @override
  void onSessionTabClosed(String workspaceId, String sessionId) {
    unawaited(_workbench.close(workspaceId, WorkbenchTabId.session(sessionId)));
  }

  @override
  void enterLanding(String workspaceId) {
    _workbench.enterLanding(workspaceId);
  }

  @override
  void closeAll(String workspaceId) {
    _workbench.closeAll(workspaceId);
  }

  @override
  void syncForeground() => _syncForeground();

  // ===== WorkbenchDomainPort (bar → domain teardown) =====

  @override
  Future<void> onTabRemoved(String workspaceId, WorkbenchTabId id) async {
    // Only session tabs own a domain runtime in ChatCubit. File/diff/shell/run
    // are torn down inline by WorkbenchShellActions before the bar removal.
    if (id.kind == WorkbenchTabKind.session) {
      await _chat.teardownSession(id.id);
    }
  }

  // ===== Foreground-session mirror =====

  void _syncForeground() {
    final workspaceId = _chat.tabStore.activeWorkspaceId;
    if (workspaceId.isEmpty) {
      _chat.setForegroundSession(null, '');
      return;
    }
    final activeId = _workbench.centerActiveId(workspaceId);
    if (activeId == null || activeId.kind != WorkbenchTabKind.session) {
      _chat.setForegroundSession(null, '');
      return;
    }
    final tab = _chat.tabStore.openTabBySessionId(activeId.id);
    _chat.setForegroundSession(activeId.id, tab?.selectedMemberId ?? '');
  }
}
