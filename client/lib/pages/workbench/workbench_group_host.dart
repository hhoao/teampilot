import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/chat/model/chat_tab.dart';
import '../../cubits/chat_cubit.dart';
import '../../cubits/cli_presets_cubit.dart';
import '../../cubits/editor_cubit.dart';
import '../../cubits/launch_profile_cubit.dart';
import '../../cubits/workbench/tab_strip.dart';
import '../../cubits/workbench/workbench_cubit.dart';
import '../../cubits/workbench/workbench_tab.dart';
import '../../cubits/workspace_landing_context_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/team_config.dart';
import '../../models/workspace.dart';
import '../../services/commands/command_ids.dart';
import '../../services/commands/command_tooltip.dart';
import '../../services/terminal/workspace_shell_connector.dart';
import '../../services/workbench/workbench_shell_actions.dart';
import '../../services/workbench/workbench_shell_launcher.dart';
import '../../services/workbench/workbench_tab_projection.dart';
import '../../services/workspace/workspace_tools_scope.dart';
import '../../utils/workspace/workspace_active_context.dart';
import '../../utils/workspace/workspace_chrome_profile.dart';
import '../../widgets/workspace_terminal/workspace_terminal_new_session_menu.dart';
import '../../widgets/workspace_terminal_panel.dart';
import '../../widgets/workbench/workbench_split_layout_view.dart';
import '../../widgets/workbench/workbench_tab_drag.dart';
import '../chat/chat_page_shell_probe.dart';
import '../chat/chat_workbench_slice.dart';
import '../chat/session_tab_cli.dart';
import '../home_workspace/workspace/workspace_chat_pane.dart';
import '../workspace_shell/workspace_shell.dart';
import '../workspace_shell/workspace_shell_tabs.dart';
import 'workbench_body.dart';

/// One editor group's pane inside the center workbench split view: a
/// [WorkspaceShell] (tab bar + body) bound to the group's own [TabStrip],
/// wrapped in a focus frame ([SplitGroupFocusFrame]) and a drag drop region
/// ([WorkbenchTabDropRegions], body only — the tab strip header stays outside
/// so plain clicks never dispatch drops).
///
/// Tab interactions route through [WorkbenchShellActions] by tab id (the cubit
/// resolves the owning group); group-scoped mutations (reorder, close-all,
/// landing entry, pin toggle) focus this group first so they always target it.
/// The body slot is the group's active tab body (session keep-alive stack /
/// file / diff) or the landing pane while the group's strip is in landing.
class WorkbenchGroupHost extends StatelessWidget {
  const WorkbenchGroupHost({
    required this.workspace,
    required this.workspaceId,
    required this.tabScopeId,
    required this.cwd,
    this.additionalPaths = const [],
    required this.groupId,
    required this.strip,
    required this.focused,
    required this.routeActive,
    required this.chatState,
    required this.runtimeTabs,
    required this.editorBucket,
    required this.shellTitles,
    required this.showTabBar,
    required this.splitEnabled,
    this.holdHandle,
    this.sessionId,
    this.actions = const [],
    this.landingBuilder,
    super.key,
  });

  final Workspace workspace;
  final String workspaceId;
  final String tabScopeId;

  /// Working directory for new terminals opened from this group's tab bar.
  final String cwd;

  /// Extra workspace folders for the multi-root file tree / source control.
  final List<String> additionalPaths;

  /// This group's id within the center split layout.
  final String groupId;

  /// This group's strip — single source of the group's tabs and active tab.
  final TabStrip strip;

  /// Whether this group currently holds the workbench focus (focus frame).
  final bool focused;
  final bool routeActive;

  /// Snapshot of the scoped [ChatState] (sessions list, launch error) from the
  /// owning shell's [ChatCubit] builder.
  final ChatState chatState;

  /// Runtime tabs for the scope (projection input; per-tab CLI resolution).
  final List<ChatTab> runtimeTabs;

  /// Editor bucket of the workspace (diff titles in the projection).
  final WorkspaceEditorBucket editorBucket;

  /// Resolved titles of the workspace shell terminal entries.
  final Map<String, String> shellTitles;

  /// Master switch for this group's tab strip row.
  final bool showTabBar;

  /// Whether split interactions (divider drags, split menu, tab drags) are
  /// available (wide viewport; narrow shows only the focused group).
  final bool splitEnabled;

  final WorkspaceTerminalHoldHandle? holdHandle;

  /// Route-level session id hint, forwarded to the session bodies.
  final String? sessionId;

  /// Team actions rendered in this group's action row (multi-group only; the
  /// single-group case renders them once above the split view instead).
  final List<Widget> actions;

  /// Builds the per-group landing pane. Defaults to [WorkspaceChatPane] bound
  /// to this group's strip landing fields; injectable for tests.
  final Widget Function(BuildContext context, TabStrip strip)? landingBuilder;

  @override
  Widget build(BuildContext context) {
    final chat = context.read<ChatCubit>();
    final workbench = context.read<WorkbenchCubit>();
    final order = strip.order;
    final activeId = strip.activeId;
    final activeTab = activeId?.kind == WorkbenchTabKind.session
        ? chat.tabStore.openTabBySessionId(activeId!.id)
        : null;
    // The group's chrome resolves from its OWN active session, not the
    // (focused) strip's — each group may host a different team context.
    final activeContext = _resolveActiveContext(context);
    final isPersonalContext = activeContext.isPersonal;
    final teamConfig = activeContext.team;
    final tabById = {for (final t in runtimeTabs) t.info.id: t};
    final sessionIds = [
      for (final t in order)
        if (t.kind == WorkbenchTabKind.session) t.id,
    ];
    // Simple-mode presets are session/landing-scoped, not identity-scoped, so
    // the personal fallback CLI is always null here (mirrors the old shell).
    final sessionCli = <String, CliTool?>{
      for (final id in sessionIds)
        id: () {
          final runtimeTab = tabById[id];
          if (runtimeTab == null) return null;
          return resolveSessionTabCli(
            tab: runtimeTab,
            sessions: chatState.sessions,
            isPersonal: isPersonalContext,
            team: teamConfig,
            personalFallbackCli: null,
            globalPresets: context.read<CliPresetsCubit>().state.presets,
          );
        }(),
    };
    // Pinned state lives on the strip (TabStrip.pinnedIds); the persisted
    // session pin (repo) is unioned in for sessions whose strip pin has not
    // been seeded yet (fresh launch).
    final persistedPinned = <WorkbenchTabId>{
      for (final t in order)
        if (t.kind == WorkbenchTabKind.session &&
            chatState.sessions
                .where((s) => s.sessionId == t.id)
                .any((s) => s.pinned))
          t,
    };
    final pinnedTabIds = strip.pinnedIds.union(persistedPinned);
    final tabs = projectWorkbenchTabs(
      tabOrder: order,
      sessionTitles: const {},
      sessionWorking: const {},
      sessionCli: sessionCli,
      pinnedTabIds: pinnedTabIds,
      editorBucket: editorBucket,
      previewTabIds: strip.previewIds,
      shellTitles: shellTitles,
      sessionAccent: Theme.of(context).colorScheme.primary,
    );
    final activeTabIndex = activeId == null
        ? -1
        : order
              .indexOf(activeId)
              .clamp(0, tabs.isEmpty ? 0 : tabs.length - 1);

    // Split entries / tab drags only on wide layouts where the group holds
    // more than one tab (a sole tab cannot be split out — reducer no-op).
    final canSplit = splitEnabled && routeActive && order.length > 1;
    final tabDrag = splitEnabled && routeActive
        ? WorkspaceShellTabDrag(
            sourceGroupId: groupId,
            onDrop: (tab, targetGroupId, zone) => dispatchSplitDrop(
              workbench,
              workspaceId,
              tab: tab,
              sourceGroupId: groupId,
              targetGroupId: targetGroupId,
              zone: zone,
            ),
          )
        : null;

    return SplitGroupFocusFrame(
      focused: focused,
      child: Column(
        children: [
          if (actions.isNotEmpty) WorkspaceShellActionsBar(actions: actions),
          Expanded(
            child: WorkspaceShell(
              showHeader: false,
              showTabBar: showTabBar,
              breadcrumb: isPersonalContext
                  ? 'Personal / Chat / Shell chat workbench'
                  : '${teamConfig?.name ?? 'Team'} / Chat / Shell chat workbench',
              title: 'Shell chat workbench',
              subtitle: isPersonalContext
                  ? 'personal workspace / shell wrapper mode'
                  : 'target: ${teamConfig != null ? _memberName(teamConfig, activeTab) : 'team'} / shell wrapper mode',
              showNewChatButton: tabs.isNotEmpty,
              newChatTooltip: commandTooltip(
                context,
                context.l10n.workbenchStripNewMenuTooltip,
                CommandIds.sessionNewTab,
              ),
              newConversationLabel: context.l10n.homeWorkspaceNewConversation,
              newTerminalLabel: context.l10n.workspaceTerminalNewSession,
              onNewConversation: routeActive
                  ? () {
                      // Enter THIS group's landing, not just the focused one's.
                      workbench.focusGroup(workspaceId, groupId);
                      workbench.enterLanding(workspaceId);
                    }
                  : null,
              onNewTerminal: routeActive
                  ? (anchor) => unawaited(
                      _showStripNewTerminalMenu(
                        context: context,
                        workspaceId: workspaceId,
                        tabScopeId: tabScopeId,
                        cwd: cwd,
                        anchor: anchor,
                      ),
                    )
                  : null,
              tabs: tabs,
              activeTabIndex: activeTabIndex,
              onTabSelected: routeActive
                  ? (index) {
                      if (index < 0 || index >= order.length) return;
                      unawaited(
                        WorkbenchShellActions.select(
                          context: context,
                          workspaceId: workspaceId,
                          tabScopeId: tabScopeId,
                          tab: order[index],
                        ),
                      );
                    }
                  : null,
              onTabClosed: routeActive
                  ? (index) {
                      if (index < 0 || index >= order.length) return;
                      unawaited(
                        WorkbenchShellActions.closeAt(
                          context: context,
                          workspaceId: workspaceId,
                          tabScopeId: tabScopeId,
                          tab: order[index],
                        ),
                      );
                    }
                  : null,
              onTabCloseOthers: routeActive
                  ? (index) {
                      if (index < 0 || index >= order.length) return;
                      unawaited(
                        WorkbenchShellActions.closeOthers(
                          context: context,
                          workspaceId: workspaceId,
                          tabScopeId: tabScopeId,
                          keep: order[index],
                        ),
                      );
                    }
                  : null,
              onTabCloseRight: routeActive
                  ? (index) {
                      if (index < 0 || index >= order.length) return;
                      unawaited(
                        WorkbenchShellActions.closeRight(
                          context: context,
                          workspaceId: workspaceId,
                          tabScopeId: tabScopeId,
                          anchor: order[index],
                        ),
                      );
                    }
                  : null,
              onTabCloseAll: routeActive
                  ? (index) {
                      // closeAll closes the focused group — focus this one so
                      // the menu acts on the group it was opened from.
                      workbench.focusGroup(workspaceId, groupId);
                      unawaited(
                        WorkbenchShellActions.closeAll(
                          context: context,
                          workspaceId: workspaceId,
                          tabScopeId: tabScopeId,
                        ),
                      );
                    }
                  : null,
              onTabPin: routeActive
                  ? (index) {
                      if (index < 0 || index >= order.length) return;
                      final sessionId = order[index].sessionId;
                      if (sessionId == null) return;
                      // Persist (repo) and runtime (strip) stores stay in
                      // sync; the projection reads the strip union.
                      unawaited(chat.toggleSessionPin(sessionId));
                      final tabId = WorkbenchTabId.session(sessionId);
                      final groupStrip =
                          workbench.centerLayout(workspaceId).groups[groupId];
                      if (groupStrip == null) return;
                      if (groupStrip.pinnedIds.contains(tabId)) {
                        workbench.unpin(workspaceId, tabId);
                      } else {
                        workbench.pin(workspaceId, tabId);
                      }
                    }
                  : null,
              onTabSplitRight: canSplit
                  ? (index) {
                      if (index < 0 || index >= order.length) return;
                      workbench.splitTab(
                        workspaceId,
                        order[index],
                        axis: Axis.horizontal,
                        before: false,
                      );
                    }
                  : null,
              onTabSplitDown: canSplit
                  ? (index) {
                      if (index < 0 || index >= order.length) return;
                      workbench.splitTab(
                        workspaceId,
                        order[index],
                        axis: Axis.vertical,
                        before: false,
                      );
                    }
                  : null,
              tabDrag: tabDrag,
              onTabsReorder: routeActive
                  ? (oldIndex, newIndex) {
                      // reorder mutates the focused group — focus this one so
                      // the drag acts on the strip it started from.
                      workbench.focusGroup(workspaceId, groupId);
                      workbench.reorder(workspaceId, oldIndex, newIndex);
                    }
                  : null,
              actions: const [],
              child: WorkbenchTabDropRegions(
                groupId: groupId,
                child: ChatPageStructuralBodyProbe(
                  key: chatPageStructuralBodyProbeKey,
                  child: _buildBody(
                    context,
                    isPersonalContext: isPersonalContext,
                    teamConfig: teamConfig,
                    activeTab: activeTab,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The group's body slot: its active tab's surface, or the landing pane
  /// while the strip is in landing over open tabs. A strip with no tabs at all
  /// is the workspace start page, which the workspace split pane already hosts
  /// above this shell — it paints nothing here (unchanged single-group flow).
  Widget _buildBody(
    BuildContext context, {
    required bool isPersonalContext,
    required TeamProfile? teamConfig,
    required ChatTab? activeTab,
  }) {
    if (strip.landingActive && strip.order.isNotEmpty) {
      final builder = landingBuilder;
      if (builder != null) return builder(context, strip);
      final workbench = context.read<WorkbenchCubit>();
      final returnTab = strip.landingReturnTabId;
      return WorkspaceChatPane(
        workspace: workspace,
        initialText: strip.landingInitialText,
        initialTextRevision: strip.landingInitialTextRevision,
        referencedSessionId: strip.landingReferenceSessionId,
        // The landing back control is scoped to THIS group: it shows when the
        // group's strip remembers a returnable tab and re-activates it (which
        // also focuses the group).
        canExitLanding: returnTab != null && strip.contains(returnTab),
        onBack: () {
          if (returnTab != null) {
            workbench.activate(workspaceId, returnTab);
          }
        },
      );
    }
    return WorkbenchBody(
      workspaceId: workspaceId,
      tabScopeId: tabScopeId,
      workspace: workspace,
      groupId: groupId,
      strip: strip,
      profileId: _profileId(
        context,
        isPersonalContext: isPersonalContext,
        team: teamConfig,
      ),
      routeActive: routeActive,
      sessionId: sessionId,
      isPersonalContext: isPersonalContext,
      team: teamConfig,
      workbenchSlice: ChatWorkbenchSlice.fromScope(
        state: chatState,
        activeSessionId: strip.activeId?.sessionId,
        selectedMemberId: activeTab?.selectedMemberId ?? '',
      ),
    );
  }

  /// Resolves this group's team/personal context from its own active session
  /// (not the focused strip's).
  WorkspaceActiveContext _resolveActiveContext(
    BuildContext context,
  ) {
    final sessionId = strip.activeId?.sessionId;
    if (sessionId != null) {
      for (final session in chatState.sessions) {
        if (session.sessionId == sessionId) {
          return WorkspaceActiveContext.forSession(
            session,
            context.read<LaunchProfileCubit>(),
          );
        }
      }
    }
    return WorkspaceActiveContext.idle;
  }

  String? _profileId(
    BuildContext context, {
    required bool isPersonalContext,
    required TeamProfile? team,
  }) {
    try {
      final ctx = context.read<WorkspaceLandingContextCubit>().state.context;
      if (ctx.isPersonal) return kSimpleLaunchProfileId;
      return ctx.teamId;
    } on Object {
      if (!isPersonalContext && team != null) return team.id;
      Workspace? ws;
      for (final w in chatState.workspaces) {
        if (w.workspaceId == workspaceId) {
          ws = w;
          break;
        }
      }
      if (ws == null) return null;
      final defaultId = ws.defaultProfileId.trim();
      if (defaultId.isNotEmpty) return defaultId;
      return kSimpleLaunchProfileId;
    }
  }

  /// Subtitle member name from THIS group's active tab's selected member.
  String _memberName(TeamProfile team, ChatTab? activeTab) {
    final id = activeTab?.selectedMemberId ?? '';
    for (final m in team.members) {
      if (m.id == id) return m.name;
    }
    return team.members.isEmpty ? 'member' : team.members.first.name;
  }
}

Future<void> _showStripNewTerminalMenu({
  required BuildContext context,
  required String workspaceId,
  required String tabScopeId,
  required String cwd,
  required Offset anchor,
}) async {
  final trimmedCwd = cwd.trim();
  if (trimmedCwd.isEmpty || !context.mounted) return;
  final folders =
      WorkspaceToolsScope.maybeOf(context)?.effectiveFolders ?? const [];
  final connector = context.read<WorkspaceShellConnector>();
  final launcher = context.read<WorkbenchShellLauncher>();
  final sshFailed = context.l10n.workspaceTerminalSshConnectFailed;
  await showWorkspaceTerminalLaunchMenu(
    context: context,
    globalPosition: anchor,
    folders: folders,
    connector: connector,
    onSessionSelected: (spec, launchCwd) {
      unawaited(
        launcher.openAndSelect(
          workspaceId: workspaceId,
          tabScopeId: tabScopeId,
          cwd: launchCwd ?? trimmedCwd,
          spec: spec,
          folders: folders,
          sshConnectFailedMessage: sshFailed,
          onStateChanged: () {},
          mounted: () => context.mounted,
        ),
      );
    },
  );
}
