import 'dart:async';

import '../../cubits/chat/session_launch_host.dart';
import '../../cubits/chat_cubit.dart';
import '../../cubits/workbench/workbench_cubit.dart';
import '../../cubits/workbench/workbench_domain_port.dart';
import '../../cubits/workbench/workbench_tab.dart';

/// Domain ↔ bar handshake. Feeds the bar on session open and routes
/// domain-driven closes and landing through the bar. Bar-derived reads go
/// through [centerActiveForScope].
class WorkbenchChatBridge implements WorkbenchDomainPort, ChatWorkbenchPort {
  WorkbenchChatBridge({
    required WorkbenchCubit workbench,
    required ChatCubit chat,
  }) : _workbench = workbench,
       _chat = chat;

  final WorkbenchCubit _workbench;
  final ChatCubit _chat;

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
  WorkbenchTabId? centerActiveForScope(String workspaceId) =>
      _workbench.centerActiveId(workspaceId);

  // ===== WorkbenchDomainPort (bar → domain teardown) =====

  @override
  Future<void> onTabRemoved(String workspaceId, WorkbenchTabId id) async {
    // Only session tabs own a domain runtime in ChatCubit. File/diff/shell/run
    // are torn down inline by WorkbenchShellActions before the bar removal.
    if (id.kind == WorkbenchTabKind.session) {
      await _chat.teardownSession(id.id);
    }
  }
}
