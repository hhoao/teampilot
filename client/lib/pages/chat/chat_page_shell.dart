import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:teampilot/theme/app_toast_theme.dart';
import 'package:teampilot/widgets/app_toast/app_toast.dart';

import '../../cubits/chat_cubit.dart';
import '../../cubits/chat/model/chat_tab.dart';
import '../../cubits/cli_presets_cubit.dart';
import '../../cubits/editor_cubit.dart';
import '../../cubits/launch_profile_cubit.dart';
import '../../cubits/layout_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/layout_preferences.dart';
import '../../models/team_config.dart';
import '../../services/app/platform_utils.dart';
import '../../utils/app_keys.dart';
import '../../utils/debounce/debounce.dart';
import '../../widgets/right_tools/right_tools_panel.dart';
import '../chat_workbench.dart';
import '../workspace_shell/workspace_shell.dart';
import 'right_tools_host.dart';
import 'chat_scoped_tab_view.dart';
import 'session_tab_cli.dart';
import 'team_config_incomplete_dialog.dart';

/// Layout fields that affect [ChatPageShell] and its right-tools subtree.
/// Subscribes narrowly so persistence-only prefs (e.g. [LayoutPreferences.lastOpenedWorkspaceId])
/// do not rebuild the workbench shell on every workspace tab switch.
@immutable
class _ChatPageShellLayoutView {
  const _ChatPageShellLayoutView({
    required this.rightToolsVisible,
    required this.rightToolsWidth,
    required this.fileTreeVisible,
    required this.gitVisible,
    required this.membersVisible,
    required this.boardVisible,
  });

  final bool rightToolsVisible;
  final double rightToolsWidth;
  final bool fileTreeVisible;
  final bool gitVisible;
  final bool membersVisible;
  final bool boardVisible;

  factory _ChatPageShellLayoutView.from(LayoutPreferences preferences) {
    return _ChatPageShellLayoutView(
      rightToolsVisible: preferences.rightToolsVisible,
      rightToolsWidth: preferences.rightToolsWidth,
      fileTreeVisible: preferences.fileTreeVisible,
      gitVisible: preferences.gitVisible,
      membersVisible: preferences.membersVisible,
      boardVisible: preferences.boardVisible,
    );
  }

  LayoutPreferences get asPreferences => LayoutPreferences(
    rightToolsVisible: rightToolsVisible,
    rightToolsWidth: rightToolsWidth,
    fileTreeVisible: fileTreeVisible,
    gitVisible: gitVisible,
    membersVisible: membersVisible,
    boardVisible: boardVisible,
  );

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is _ChatPageShellLayoutView &&
            rightToolsVisible == other.rightToolsVisible &&
            rightToolsWidth == other.rightToolsWidth &&
            fileTreeVisible == other.fileTreeVisible &&
            gitVisible == other.gitVisible &&
            membersVisible == other.membersVisible &&
            boardVisible == other.boardVisible;
  }

  @override
  int get hashCode => Object.hash(
    rightToolsVisible,
    rightToolsWidth,
    fileTreeVisible,
    gitVisible,
    membersVisible,
    boardVisible,
  );
}

class ChatPageShell extends StatelessWidget {
  const ChatPageShell({
    required this.cwd,
    required this.isPersonalWorkspace,
    required this.workspaceId,
    required this.tabScopeId,
    required this.team,
    this.routeActive = true,
    this.additionalPaths = const [],
    this.sessionId,
    super.key,
  });

  final String cwd;

  /// Extra workspace folders for the multi-root file tree / source control.
  final List<String> additionalPaths;
  final String? sessionId;
  final bool isPersonalWorkspace;
  final String workspaceId;
  final String tabScopeId;
  final bool routeActive;
  final TeamProfile? team;

  @override
  Widget build(BuildContext context) {
    final toolsAsDrawer = useRightToolsAsDrawer(context);

    if (!toolsAsDrawer) {
      return _chatLaunchListener(
        context,
        _ChatPageSplitLayout(
          cwd: cwd,
          additionalPaths: additionalPaths,
          sessionId: sessionId,
          isPersonalWorkspace: isPersonalWorkspace,
          workspaceId: workspaceId,
          tabScopeId: tabScopeId,
          routeActive: routeActive,
          team: team,
        ),
      );
    }

    return _chatLaunchListener(
      context,
      _ChatPageDrawerLayout(
        cwd: cwd,
        additionalPaths: additionalPaths,
        sessionId: sessionId,
        isPersonalWorkspace: isPersonalWorkspace,
        workspaceId: workspaceId,
        tabScopeId: tabScopeId,
        routeActive: routeActive,
        team: team,
      ),
    );
  }
}

/// Desktop split: [RightToolsHost] owns layout prefs; center and right tools
/// are separate subtrees so chat/layout churn does not cross-rebuild.
class _ChatPageSplitLayout extends StatelessWidget {
  const _ChatPageSplitLayout({
    required this.cwd,
    required this.additionalPaths,
    required this.sessionId,
    required this.isPersonalWorkspace,
    required this.workspaceId,
    required this.tabScopeId,
    required this.routeActive,
    required this.team,
  });

  final String cwd;
  final List<String> additionalPaths;
  final String? sessionId;
  final bool isPersonalWorkspace;
  final String workspaceId;
  final String tabScopeId;
  final bool routeActive;
  final TeamProfile? team;

  @override
  Widget build(BuildContext context) {
    return RightToolsHost(
      onRightToolsWidthChanged: (w) =>
          context.read<LayoutCubit>().setRightToolsWidth(w),
      center: _ChatWorkspaceShell(
        cwd: cwd,
        sessionId: sessionId,
        isPersonalWorkspace: isPersonalWorkspace,
        workspaceId: workspaceId,
        tabScopeId: tabScopeId,
        routeActive: routeActive,
        team: team,
      ),
      rightTools: _ChatRightToolsPanelSlot(
        cwd: cwd,
        additionalPaths: additionalPaths,
        isPersonalWorkspace: isPersonalWorkspace,
        workspaceId: workspaceId,
        tabScopeId: tabScopeId,
      ),
    );
  }
}

/// Narrow layout subscription for the right tools panel only.
class _ChatRightToolsPanelSlot extends StatelessWidget {
  const _ChatRightToolsPanelSlot({
    required this.cwd,
    required this.additionalPaths,
    required this.isPersonalWorkspace,
    required this.workspaceId,
    required this.tabScopeId,
  });

  final String cwd;
  final List<String> additionalPaths;
  final bool isPersonalWorkspace;
  final String workspaceId;
  final String tabScopeId;

  @override
  Widget build(BuildContext context) {
    final layout = context.select<LayoutCubit, _ChatPageShellLayoutView>(
      (c) => _ChatPageShellLayoutView.from(c.state.preferences),
    );
    return RightToolsPanel(
      cwd: cwd,
      additionalPaths: additionalPaths,
      preferences: layout.asPreferences,
      panelKey: AppKeys.rightToolsPanel,
      dismissDrawerOnAction: false,
      isPersonalWorkspace: isPersonalWorkspace,
      workspaceId: workspaceId,
      toolsScopeId: tabScopeId,
    );
  }
}

class _ChatPageDrawerLayout extends StatelessWidget {
  const _ChatPageDrawerLayout({
    required this.cwd,
    required this.additionalPaths,
    required this.sessionId,
    required this.isPersonalWorkspace,
    required this.workspaceId,
    required this.tabScopeId,
    required this.routeActive,
    required this.team,
  });

  final String cwd;
  final List<String> additionalPaths;
  final String? sessionId;
  final bool isPersonalWorkspace;
  final String workspaceId;
  final String tabScopeId;
  final bool routeActive;
  final TeamProfile? team;

  @override
  Widget build(BuildContext context) {
    final layout = context.select<LayoutCubit, _ChatPageShellLayoutView>(
      (c) => _ChatPageShellLayoutView.from(c.state.preferences),
    );
    final preferences = layout.asPreferences;
    final rightToolsPanel = RightToolsPanel(
      cwd: cwd,
      additionalPaths: additionalPaths,
      preferences: preferences,
      panelKey: AppKeys.rightToolsPanel,
      dismissDrawerOnAction: true,
      isPersonalWorkspace: isPersonalWorkspace,
      workspaceId: workspaceId,
      toolsScopeId: tabScopeId,
    );

    return Scaffold(
      endDrawer: preferences.rightToolsVisible
          ? Drawer(
              width: rightToolsDrawerWidth(context, preferences),
              child: SafeArea(child: rightToolsPanel),
            )
          : null,
      body: _ChatWorkspaceShell(
        cwd: cwd,
        sessionId: sessionId,
        isPersonalWorkspace: isPersonalWorkspace,
        workspaceId: workspaceId,
        tabScopeId: tabScopeId,
        routeActive: routeActive,
        team: team,
      ),
    );
  }
}

class _ChatWorkspaceShell extends StatelessWidget {
  const _ChatWorkspaceShell({
    required this.cwd,
    required this.sessionId,
    required this.isPersonalWorkspace,
    required this.workspaceId,
    required this.tabScopeId,
    required this.routeActive,
    required this.team,
  });

  final String cwd;
  final String? sessionId;
  final bool isPersonalWorkspace;
  final String workspaceId;
  final String tabScopeId;
  final bool routeActive;
  final TeamProfile? team;

  bool _scopedTabBuildWhen(
    ChatCubit cubit,
    ChatState previous,
    ChatState next,
  ) {
    if (!routeActive) return false;
    return previous.tabs != next.tabs ||
        previous.activeTabIndex != next.activeTabIndex ||
        previous.workingSessionIds != next.workingSessionIds ||
        previous.selectedMemberId != next.selectedMemberId ||
        previous.sessionConnectingId != next.sessionConnectingId ||
        previous.sessionLaunchError != next.sessionLaunchError ||
        previous.stateVersion != next.stateVersion;
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ChatCubit>();
    return BlocBuilder<ChatCubit, ChatState>(
      buildWhen: (previous, next) =>
          _scopedTabBuildWhen(cubit, previous, next),
      builder: (context, state) {
        final view = ChatScopedTabView.resolve(cubit, tabScopeId);
        final teamConfig = team;
        final runtimeTabs = _runtimeTabsForScope(cubit, tabScopeId);
        final tabById = {for (final t in runtimeTabs) t.info.id: t};
        final personalFallbackCli = isPersonalWorkspace
            ? _personalPresetCli(context)
            : null;
        return WorkspaceShell(
          workspaceTerminalWorkingDirectory: cwd,
          workspaceWorkspaceId: tabScopeId,
          showHeader: false,
          breadcrumb: isPersonalWorkspace
              ? 'Personal / Chat / Shell chat workbench'
              : '${teamConfig!.name} / Chat / Shell chat workbench',
          title: 'Shell chat workbench',
          subtitle: isPersonalWorkspace
              ? 'personal workspace / shell wrapper mode'
              : 'target: ${cubit.selectedMemberName(teamConfig!)} / shell wrapper mode',
          tabs: view.tabs
              .map(
                (t) {
                  final runtimeTab = tabById[t.id];
                  final cli = runtimeTab == null
                      ? null
                      : resolveSessionTabCli(
                          tab: runtimeTab,
                          sessions: state.sessions,
                          isPersonal: isPersonalWorkspace,
                          team: teamConfig,
                          personalFallbackCli: personalFallbackCli,
                          globalPresets:
                              context.watch<CliPresetsCubit>().state.presets,
                        );
                  return TabInfo(
                    id: t.id,
                    title: t.title,
                    working: view.workingSessionIds.contains(t.id),
                    cli: cli,
                    accentColor: Theme.of(context).colorScheme.primary,
                  );
                },
              )
              .toList(),
          activeTabIndex: view.activeTabIndex,
          onTabSelected: routeActive
              ? (index) => cubit.selectTab(index)
              : null,
          onTabClosed: routeActive
              ? (index) => cubit.closeTab(index)
              : null,
          onTabCloseOthers: routeActive
              ? (index) => cubit.closeOtherTabs(index)
              : null,
          onTabCloseRight: routeActive
              ? (index) => cubit.closeRightTabs(index)
              : null,
          showRightToolsVisibilityToggle: true,
          actions: isPersonalWorkspace
              ? const []
              : _chatActions(context, teamConfig!),
          child: ChatWorkbench(
            workspaceId: workspaceId,
            tabScopeId: tabScopeId,
            routeActive: routeActive,
            sessionId: sessionId,
            isPersonalWorkspace: isPersonalWorkspace,
            team: team,
            workbenchSlice: view.workbenchSlice,
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
    return cubit.tabStore.tabs;
  }
  return bucket;
}

CliTool? _personalPresetCli(BuildContext context) {
  final personal = context.read<LaunchProfileCubit>().activePersonal;
  final activePresetId = personal?.activePresetId;
  if (activePresetId == null || activePresetId.isEmpty) return null;
  return context.read<CliPresetsCubit>().state.presetById(activePresetId)?.cli;
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
            ? AppToastVariant.warning
            : AppToastVariant.info,
      );
      listenerContext.read<ChatCubit>().clearSnackbarMessage();
    },
    child: BlocListener<EditorCubit, EditorState>(
      listenWhen: (previous, next) =>
          previous.snackbarMessage != next.snackbarMessage &&
          next.snackbarMessage != null,
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
