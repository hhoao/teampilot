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
    this.replacedPreviewTeardown,
  }) : _workbench = workbench,
       _chat = chat;

  final WorkbenchCubit _workbench;
  final ChatCubit _chat;

  /// Optional domain teardown for a *non-session* tab displaced from the
  /// preview slot (file/diff/shell/run). Sessions are handled inline; null
  /// keeps the bridge inert in tests that only exercise session tabs.
  final void Function(String workspaceId, WorkbenchTabId replaced)?
      replacedPreviewTeardown;

  /// Session domain staged a new/reused session tab; surface it in the bar.
  void onSessionTabOpened(
    String workspaceId,
    String sessionId, {
    bool preview = false,
    bool activate = true,
  }) {
    final replaced = _workbench.openSession(
      workspaceId,
      sessionId,
      preview: preview,
      activate: activate,
    );
    // Active tab is bar-derived; re-push so presence tracks the session just
    // surfaced (sidebar / reuse), not the previous simple or team tab.
    if (activate) _chat.pushPresenceTarget();
    if (replaced == null) return;
    if (replaced.kind == WorkbenchTabKind.session) {
      final replacedTab = _chat.tabStore.openTabBySessionId(replaced.id);
      if (replacedTab?.isRunning == true) {
        // The displaced preview is a live agent: re-pin it in the bar without
        // stealing activation instead of tearing it down.
        _workbench.openSession(
          workspaceId,
          replaced.id,
          preview: false,
          activate: false,
        );
      } else {
        // A preview slot replaced in place is no longer in the bar; tear its
        // domain runtime down so it cannot be resurrected as an orphan.
        unawaited(_chat.teardownSession(replaced.id));
      }
    } else if (replacedPreviewTeardown != null) {
      replacedPreviewTeardown!(workspaceId, replaced);
    }
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
