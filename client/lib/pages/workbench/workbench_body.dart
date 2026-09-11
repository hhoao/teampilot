import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/chat/model/chat_tab.dart';
import '../../cubits/chat_cubit.dart';
import '../../cubits/workbench/tab_strip.dart';
import '../../cubits/workbench/workbench_tab.dart';
import '../../models/team_config.dart';
import '../../models/workspace.dart';
import '../chat/chat_workbench_slice.dart';
import '../chat/keep_alive_session_stack.dart';
import '../chat_workbench.dart';
import 'diff_editor_surface.dart';
import 'file_editor_surface.dart';

/// Center workbench body of ONE editor group: session / file / diff. Shell and
/// run live floating.
///
/// The active tab comes from the group's own [strip] — each split group hosts
/// its own keep-alive session stack scoped to the session tabs it owns. The
/// landing (workspace start page) is owned by the workspace split pane or the
/// group host, which swap this body out for the compose surface while the
/// group's strip is in landing — a null active here can only be the same-frame
/// transient of that swap and paints nothing.
class WorkbenchBody extends StatelessWidget {
  const WorkbenchBody({
    required this.workspaceId,
    required this.tabScopeId,
    required this.workspace,
    required this.groupId,
    required this.strip,
    required this.workbenchSlice,
    this.profileId,
    this.routeActive = true,
    this.sessionId,
    this.isPersonalContext = false,
    this.team,
    super.key,
  });

  final String workspaceId;
  final String tabScopeId;
  final Workspace workspace;

  /// Owning split-group id (identity / diagnostics; tab state comes from
  /// [strip]).
  final String groupId;

  /// This group's strip — the single source of the group's active tab.
  final TabStrip strip;
  final ChatWorkbenchSlice workbenchSlice;
  final String? profileId;
  final bool routeActive;
  final String? sessionId;
  final bool isPersonalContext;
  final TeamProfile? team;

  @override
  Widget build(BuildContext context) {
    final active = strip.activeId;
    if (active == null) {
      return const SizedBox.shrink();
    }
    if (!isCenterStripWorkbenchTab(active.kind)) {
      assert(() {
        debugPrint(
          'WorkbenchBody: shell/run tabs must not be active on the '
          'center workbench strip',
        );
        return true;
      }());
      return const SizedBox.shrink();
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        if (active.kind == WorkbenchTabKind.session)
          _SessionKeepAliveHosts(
            workspaceId: workspaceId,
            tabScopeId: tabScopeId,
            profileId: profileId,
            routeActive: routeActive,
            sessionId: sessionId,
            isPersonalContext: isPersonalContext,
            team: team,
            workbenchSlice: workbenchSlice,
            sessionIds: [
              for (final t in strip.order)
                if (t.kind == WorkbenchTabKind.session) t.id,
            ],
          )
        else if (active.kind == WorkbenchTabKind.file)
          FileEditorSurface(
            key: ValueKey(active.id),
            workspaceId: workspaceId,
            path: active.id,
          )
        else if (active.kind == WorkbenchTabKind.diff)
          DiffEditorSurface(
            key: ValueKey(active.id),
            workspaceId: workspaceId,
            diffKey: active.id,
          ),
      ],
    );
  }
}

/// One [ChatWorkbench] per open session of THIS group, kept alive inside a
/// [KeepAliveSessionStack]. Each host is scoped to its own session id (per-host
/// [ChatWorkbenchSlice]) so switching conversations changes only the active
/// index — no remount, no history reload.
///
/// The stack is scoped to the group's own session tabs ([sessionIds]): a tab
/// lives in exactly one split group, so a session's host mounts in exactly one
/// group's stack even when several groups render side by side.
///
/// Each host is built once inside a [_SessionHostSlot] and cached: parent
/// rebuilds (session added/removed elsewhere, member switches, route changes)
/// only re-run the slot's param comparison, so N open sessions do not multiply
/// the rebuild cost of unrelated workbench state.
class _SessionKeepAliveHosts extends StatelessWidget {
  const _SessionKeepAliveHosts({
    required this.workspaceId,
    required this.tabScopeId,
    required this.profileId,
    required this.routeActive,
    required this.sessionId,
    required this.isPersonalContext,
    required this.team,
    required this.workbenchSlice,
    required this.sessionIds,
  });

  final String workspaceId;
  final String tabScopeId;
  final String? profileId;
  final bool routeActive;
  final String? sessionId;
  final bool isPersonalContext;
  final TeamProfile? team;
  final ChatWorkbenchSlice workbenchSlice;

  /// Session tab ids owned by this group's strip (strip order).
  final List<String> sessionIds;

  @override
  Widget build(BuildContext context) {
    final chat = context.read<ChatCubit>();
    // Select a stable composite key of tab structure + per-tab mutable fields
    // so this widget rebuilds only when session tabs are added/removed or their
    // selected member / launch error changes — not on every ChatState emit.
    final _ = context.select<ChatCubit, String>((c) {
      final tabs = c.tabStore.tabsForWorkspace(tabScopeId);
      return tabs
          .map((t) => '${t.info.id}:${t.selectedMemberId}:${t.info.launchError}')
          .join(',');
    });
    final groupSessions = sessionIds.toSet();
    final tabs = chat.tabStore
        .tabsForWorkspace(tabScopeId)
        .where((t) => groupSessions.contains(t.info.id))
        .toList(growable: false);
    final activeId = workbenchSlice.activeSessionId;
    return KeepAliveSessionStack(
      sessionIds: [for (final t in tabs) t.info.id],
      activeSessionId: activeId,
      hosts: [
        for (var i = 0; i < tabs.length; i++)
          _SessionHostSlot(
            key: ValueKey('session-host-${tabs[i].info.id}'),
            tabSessionId: tabs[i].info.id,
            workspaceId: workspaceId,
            tabScopeId: tabScopeId,
            profileId: profileId,
            // Only the active host is route-active: offstage hosts must not
            // spawn placeholder shells or claim terminal input focus.
            routeActive: routeActive && tabs[i].info.id == activeId,
            sessionId: sessionId,
            isPersonalContext: isPersonalContext,
            team: team,
            workbenchSlice: _sliceForSession(chat.state, tabs[i]),
          ),
      ],
    );
  }
}

/// Caches the built [ChatWorkbench] for one session. [build] re-creates the
/// host only when its own [routeActive] or per-session [workbenchSlice]
/// changes; parent-driven rebuilds otherwise short-circuit on the cached
/// widget instance and do not touch the host subtree.
class _SessionHostSlot extends StatefulWidget {
  const _SessionHostSlot({
    required this.tabSessionId,
    required this.workspaceId,
    required this.tabScopeId,
    required this.profileId,
    required this.routeActive,
    required this.sessionId,
    required this.isPersonalContext,
    required this.team,
    required this.workbenchSlice,
    super.key,
  });

  /// The tab's own session id; identity for the cached host.
  final String tabSessionId;
  final String workspaceId;
  final String tabScopeId;
  final String? profileId;
  final bool routeActive;

  /// Route-level session id, forwarded to [ChatWorkbench].
  final String? sessionId;
  final bool isPersonalContext;
  final TeamProfile? team;
  final ChatWorkbenchSlice workbenchSlice;

  @override
  State<_SessionHostSlot> createState() => _SessionHostSlotState();
}

class _SessionHostSlotState extends State<_SessionHostSlot> {
  Widget? _cachedChild;
  bool? _cachedRouteActive;
  ChatWorkbenchSlice? _cachedSlice;
  String? _cachedProfileId;
  bool? _cachedIsPersonal;
  TeamProfile? _cachedTeam;
  String? _cachedSessionId;

  @override
  Widget build(BuildContext context) {
    if (_cachedChild == null ||
        _cachedRouteActive != widget.routeActive ||
        _cachedSlice != widget.workbenchSlice ||
        _cachedProfileId != widget.profileId ||
        _cachedIsPersonal != widget.isPersonalContext ||
        _cachedTeam != widget.team ||
        _cachedSessionId != widget.sessionId) {
      _cachedChild = ChatWorkbench(
        key: ValueKey('session-host-${widget.tabSessionId}'),
        workspaceId: widget.workspaceId,
        tabScopeId: widget.tabScopeId,
        profileId: widget.profileId,
        routeActive: widget.routeActive,
        sessionId: widget.sessionId,
        isPersonalContext: widget.isPersonalContext,
        team: widget.team,
        workbenchSlice: widget.workbenchSlice,
      );
      _cachedRouteActive = widget.routeActive;
      _cachedSlice = widget.workbenchSlice;
      _cachedProfileId = widget.profileId;
      _cachedIsPersonal = widget.isPersonalContext;
      _cachedTeam = widget.team;
      _cachedSessionId = widget.sessionId;
    }
    return _cachedChild!;
  }
}

/// Scopes a workbench slice to a single session so an offstage host resolves
/// only its own tab/shell — never the active conversation's.
ChatWorkbenchSlice _sliceForSession(ChatState state, ChatTab tab) {
  return ChatWorkbenchSlice(
    activeSessionId: tab.info.id,
    selectedMemberId: tab.selectedMemberId,
    sessionLaunchError: tab.info.launchError,
  );
}
