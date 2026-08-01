import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/widgets/app_toast/app_toast.dart';

import '../../cubits/chat_cubit.dart';
import '../../cubits/chat/model/chat_tab.dart';
import '../../cubits/cli_presets_cubit.dart';
import '../../cubits/editor_cubit.dart';
import '../../cubits/launch_profile_cubit.dart';
import '../../cubits/run_cubit.dart';
import '../../cubits/workbench/workbench_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../utils/workspace/workspace_chrome_profile.dart';
import '../../models/run/run_session.dart';
import '../../models/team_config.dart';
import '../../services/run/run_panel_session.dart';
import '../../services/terminal/workspace_shell_connector.dart';
import '../../services/terminal/workspace_terminal_registry.dart';
import '../../services/terminal/workspace_terminal_title_resolver.dart';
import '../../services/workbench/workbench_shell_actions.dart';
import '../../services/workbench/workbench_shell_launcher.dart';
import '../../services/workbench/workbench_tab_projection.dart';
import '../../services/workspace/workspace_tools_scope.dart';
import '../../utils/ui/app_keys.dart';
import '../../utils/debounce/debounce.dart';
import '../../utils/workspace/workspace_active_context.dart';
import '../../cubits/workspace_landing_context_cubit.dart';
import '../../widgets/workbench/workbench_session_sync.dart';
import '../../widgets/workbench/workbench_shell_run_sync.dart';
import '../../widgets/workspace_terminal/workspace_terminal_new_session_menu.dart';
import '../../widgets/workspace_terminal_panel.dart';
import '../workbench/workbench_body.dart';
import '../workspace_shell/workspace_shell.dart';
import 'chat_page_structural_signal.dart';
import 'chat_page_shell_probe.dart';
import 'chat_scoped_tab_view.dart';
import 'session_tab_cli.dart';
import 'session_workbench_view_toggle.dart';
import 'team_config_incomplete_dialog.dart';

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
    onSessionSelected: (spec) {
      unawaited(
        launcher.openAndSelect(
          workspaceId: workspaceId,
          tabScopeId: tabScopeId,
          cwd: trimmedCwd,
          spec: spec,
          sshConnectFailedMessage: sshFailed,
          onStateChanged: () {},
          mounted: () => context.mounted,
        ),
      );
    },
  );
}

class ChatPageShell extends StatelessWidget {
  const ChatPageShell({
    required this.cwd,
    required this.workspaceId,
    required this.tabScopeId,
    this.routeActive = true,
    this.additionalPaths = const [],
    this.sessionId,
    this.holdHandle,
    super.key,
  });

  final String cwd;

  /// Extra workspace folders for the multi-root file tree / source control.
  final List<String> additionalPaths;
  final String? sessionId;
  final String workspaceId;
  final String tabScopeId;
  final bool routeActive;
  final WorkspaceTerminalHoldHandle? holdHandle;

  @override
  Widget build(BuildContext context) {
    // Center-only: geometry (sidebar / right tools / bottom terminal) is owned
    // by `WorkspaceIdeShell` above this widget. `ChatPageShell` now renders just
    // the center workbench column.
    return _chatLaunchListener(
      context,
      _ChatWorkspaceShell(
        cwd: cwd,
        sessionId: sessionId,
        workspaceId: workspaceId,
        tabScopeId: tabScopeId,
        routeActive: routeActive,
        holdHandle: holdHandle,
      ),
    );
  }
}

class _ChatWorkspaceShell extends StatelessWidget {
  const _ChatWorkspaceShell({
    required this.cwd,
    required this.sessionId,
    required this.workspaceId,
    required this.tabScopeId,
    required this.routeActive,
    this.holdHandle,
  });

  final String cwd;
  final String? sessionId;
  final String workspaceId;
  final String tabScopeId;
  final bool routeActive;
  final WorkspaceTerminalHoldHandle? holdHandle;

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
      final workspace = context
          .read<ChatCubit>()
          .state
          .workspaces
          .where((w) => w.workspaceId == workspaceId)
          .firstOrNull;
      if (workspace == null) return null;
      final defaultId = workspace.defaultProfileId.trim();
      if (defaultId.isNotEmpty) return defaultId;
      return kSimpleLaunchProfileId;
    }
  }

  bool _scopedTabBuildWhen(
    ChatCubit cubit,
    ChatState previous,
    ChatState next,
  ) {
    if (!routeActive) return false;
    final prevSignal = chatPageStructuralSignal(
      state: previous,
      tabStore: cubit.tabStore,
      tabScopeId: tabScopeId,
    );
    final nextSignal = chatPageStructuralSignal(
      state: next,
      tabStore: cubit.tabStore,
      tabScopeId: tabScopeId,
    );
    return prevSignal != nextSignal;
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ChatCubit>();
    return BlocBuilder<ChatCubit, ChatState>(
      buildWhen: (previous, next) => _scopedTabBuildWhen(cubit, previous, next),
      builder: (context, state) {
        final view = ChatScopedTabView.resolve(cubit, tabScopeId);
        final active = WorkspaceActiveContext.resolve(
          chat: cubit,
          launchProfiles: context.read<LaunchProfileCubit>(),
          tabScopeId: tabScopeId,
        );
        final isPersonalContext = active.isPersonal;
        final teamConfig = active.team;
        final runtimeTabs = _runtimeTabsForScope(cubit, tabScopeId);
        final tabById = {for (final t in runtimeTabs) t.info.id: t};
        final personalFallbackCli = isPersonalContext
            ? _personalPresetCli(context)
            : null;
        final sessionIds = view.tabs.map((t) => t.id).toList(growable: false);
        final workspace = state.workspaces
            .where((w) => w.workspaceId == workspaceId)
            .firstOrNull;
        if (workspace == null) {
          return const SizedBox.shrink();
        }

        return WorkbenchSessionSync(
          workspaceId: workspaceId,
          sessionIds: sessionIds,
          activeSessionId: view.workbenchSlice.activeSessionId,
          newChatActive: view.newChatActive,
          child: WorkbenchShellRunSync(
            workspaceId: workspaceId,
            tabScopeId: tabScopeId,
            holdHandle: holdHandle,
            child: BlocBuilder<WorkbenchCubit, WorkbenchState>(
              buildWhen: (prev, next) =>
                  prev.bucket(workspaceId) != next.bucket(workspaceId),
              builder: (context, workbenchState) {
                final editorBucket = context
                    .select<EditorCubit, WorkspaceEditorBucket>(
                      (c) => c.state.bucket(workspaceId),
                    );
                final order = workbenchState.bucket(workspaceId).tabOrder;
                final activeId = workbenchState.bucket(workspaceId).activeTabId;
                const sessionTitles = <String, String>{};
                const sessionWorking = <String, bool>{};
                final sessionCli = <String, CliTool?>{
                  for (final t in view.tabs)
                    t.id: () {
                      final runtimeTab = tabById[t.id];
                      if (runtimeTab == null) return null;
                      return resolveSessionTabCli(
                        tab: runtimeTab,
                        sessions: state.sessions,
                        isPersonal: isPersonalContext,
                        team: teamConfig,
                        personalFallbackCli: personalFallbackCli,
                        globalPresets: context
                            .read<CliPresetsCubit>()
                            .state
                            .presets,
                      );
                    }(),
                };
                final sessionPinned = {
                  for (final s in state.sessions)
                    if (sessionIds.contains(s.sessionId)) s.sessionId: s.pinned,
                };
                final shellGroup = context
                    .read<WorkspaceTerminalRegistry>()
                    .groupFor(tabScopeId);
                final shellEntries = shellGroup.entries;
                final shellTitles = {
                  for (final entry in shellEntries)
                    entry.id: WorkspaceTerminalTitleResolver.tabTitle(
                      entry: entry,
                      siblings: shellEntries,
                      baseLabel: entry.titleLabel.isEmpty
                          ? '…'
                          : entry.titleLabel,
                    ),
                };
                final runSessions = context.watch<RunCubit>().state.sessions;
                final runTitles = {
                  for (final session in runSessions)
                    if (sessionUsesRunPanel(session))
                      session.id: session.owned.configuration.name,
                };
                final runWorking = {
                  for (final session in runSessions)
                    if (sessionUsesRunPanel(session) &&
                        (session.status == RunSessionStatus.running ||
                            session.status == RunSessionStatus.starting))
                      session.id: true,
                };
                final tabs = projectWorkbenchTabs(
                  tabOrder: order,
                  sessionTitles: sessionTitles,
                  sessionWorking: sessionWorking,
                  sessionCli: sessionCli,
                  sessionPinned: sessionPinned,
                  editorBucket: editorBucket,
                  previewTabIds: workbenchState
                      .bucket(workspaceId)
                      .previewTabIds,
                  shellTitles: shellTitles,
                  runTitles: runTitles,
                  runWorking: runWorking,
                  sessionAccent: Theme.of(context).colorScheme.primary,
                );
                final activeTabIndex = activeId == null
                    ? -1
                    : order
                          .indexOf(activeId)
                          .clamp(0, tabs.isEmpty ? 0 : tabs.length - 1);

                return WorkspaceShell(
                  showHeader: false,
                  breadcrumb: isPersonalContext
                      ? 'Personal / Chat / Shell chat workbench'
                      : '${teamConfig?.name ?? 'Team'} / Chat / Shell chat workbench',
                  title: 'Shell chat workbench',
                  subtitle: isPersonalContext
                      ? 'personal workspace / shell wrapper mode'
                      : 'target: ${teamConfig != null ? cubit.selectedMemberName(teamConfig) : 'team'} / shell wrapper mode',
                  showNewChatButton: tabs.isNotEmpty,
                  newChatTooltip: context.l10n.workbenchStripNewMenuTooltip,
                  newConversationLabel:
                      context.l10n.homeWorkspaceNewConversation,
                  newTerminalLabel: context.l10n.workspaceTerminalNewSession,
                  onNewConversation: routeActive
                      ? () {
                          context.read<WorkbenchCubit>().clearActive(
                            workspaceId,
                          );
                          cubit.enterNewChat(tabScopeId);
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
                  onTabPin: routeActive
                      ? (index) {
                          if (index < 0 || index >= order.length) return;
                          final sessionId = order[index].sessionId;
                          if (sessionId == null) return;
                          unawaited(cubit.toggleSessionPin(sessionId));
                        }
                      : null,
                  onTabsReorder: routeActive
                      ? (oldIndex, newIndex) {
                          context.read<WorkbenchCubit>().reorderTabs(
                            workspaceId,
                            oldIndex,
                            newIndex,
                          );
                        }
                      : null,
                  tabBarTrailing: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: SessionWorkbenchViewToggle(
                      workspaceId: workspaceId,
                      tabScopeId: tabScopeId,
                      team: teamConfig,
                    ),
                  ),
                  actions: isPersonalContext || teamConfig == null
                      ? const []
                      : _chatActions(context, teamConfig),
                  child: ChatPageStructuralBodyProbe(
                    key: chatPageStructuralBodyProbeKey,
                    child: WorkbenchBody(
                      workspaceId: workspaceId,
                      tabScopeId: tabScopeId,
                      workspace: workspace,
                      profileId: _profileId(
                        context,
                        isPersonalContext: isPersonalContext,
                        team: teamConfig,
                      ),
                      routeActive: routeActive,
                      sessionId: sessionId,
                      isPersonalContext: isPersonalContext,
                      team: teamConfig,
                      workbenchSlice: view.workbenchSlice,
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  List<Widget> _chatActions(BuildContext context, TeamProfile team) {
    return [
      IconButton.filledTonal(
        key: AppKeys.openTeamLeadButton,
        tooltip: 'Open team-lead',
        onPressed: throttledOnPressed('chat_open_team_lead', () {
          final lead = team.members.where((m) => m.id == 'team-lead');
          if (lead.isEmpty) {
            context.read<ChatCubit>().addSystemMessage(
              'FlashskyAI requires a member named team-lead.',
            );
            return;
          }
          unawaited(
            context.read<ChatCubit>().openMemberTab(
              team,
              lead.first,
              workspaceCwd: cwd,
            ),
          );
        }),
        icon: Icon(Icons.person_outline),
      ),
      IconButton.filled(
        key: AppKeys.openTeamButton,
        tooltip: 'Open Team',
        onPressed: throttledAsync(
          'chat_launch_all_members',
          () => context.read<ChatCubit>().launchAllMembers(
            team,
            workspaceCwd: cwd,
          ),
        ),
        icon: Icon(Icons.groups_outlined),
      ),
    ];
  }
}

List<ChatTab> _runtimeTabsForScope(ChatCubit cubit, String tabScopeId) {
  final bucket = cubit.tabStore.tabsForWorkspace(tabScopeId);
  if (bucket.isNotEmpty) return bucket;
  if (cubit.tabStore.activeWorkspaceId == tabScopeId) {
    return cubit.tabStore.activeTabs;
  }
  return bucket;
}

CliTool? _personalPresetCli(BuildContext context) {
  // Simple mode presets are session/landing-scoped, not identity-scoped.
  return null;
}

Widget _chatLaunchListener(BuildContext context, Widget child) {
  return BlocListener<ChatCubit, ChatState>(
    listenWhen: (previous, next) =>
        previous.snackbarMessage != next.snackbarMessage &&
        next.snackbarMessage != null,
    listener: (listenerContext, state) {
      if (!listenerContext.mounted) return;
      final code = state.snackbarMessage;
      if (code == null) return;
      final message = code == 'claude_credentials_missing'
          ? listenerContext.l10n.claudeLaunchCredentialsMissingWarning
          : code;
      AppToast.show(
        listenerContext,
        message: message,
        variant: code == 'claude_credentials_missing'
            ? TpToastVariant.warning
            : TpToastVariant.info,
      );
      listenerContext.read<ChatCubit>().clearSnackbarMessage();
    },
    child: BlocListener<EditorCubit, EditorState>(
      listenWhen: (previous, next) =>
          previous.snackbarMessage != next.snackbarMessage &&
          next.snackbarMessage != null &&
          !isDiffEditorSurfaceSnackbar(next.snackbarMessage!),
      listener: (listenerContext, state) {
        if (!listenerContext.mounted) return;
        final code = state.snackbarMessage;
        if (code == null) return;
        final message = listenerContext.l10n.editorSnackbarMessage(code);
        AppToast.show(listenerContext, message: message);
        listenerContext.read<EditorCubit>().clearSnackbarMessage();
      },
      child: BlocListener<ChatCubit, ChatState>(
        listenWhen: (previous, next) =>
            previous.teamConfigValidation != next.teamConfigValidation &&
            next.teamConfigValidation != null,
        listener: (listenerContext, state) {
          final validation = state.teamConfigValidation;
          listenerContext.read<ChatCubit>().clearTeamConfigValidation();
          if (validation == null || !listenerContext.mounted) return;
          unawaited(
            showTeamConfigIncompleteDialog(listenerContext, validation),
          );
        },
        child: child,
      ),
    ),
  );
}
