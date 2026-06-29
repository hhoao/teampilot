import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:teampilot/theme/app_toast_theme.dart';
import 'package:teampilot/widgets/app_toast/app_toast.dart';

import '../../cubits/chat_cubit.dart';
import '../../cubits/editor_cubit.dart';
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
    required this.team,
  });

  final String cwd;
  final List<String> additionalPaths;
  final String? sessionId;
  final bool isPersonalWorkspace;
  final String workspaceId;
  final String tabScopeId;
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
    required this.team,
  });

  final String cwd;
  final List<String> additionalPaths;
  final String? sessionId;
  final bool isPersonalWorkspace;
  final String workspaceId;
  final String tabScopeId;
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
        team: team,
      ),
    );
  }
}

class _ShellTabModel {
  const _ShellTabModel({
    required this.tabs,
    required this.activeTabIndex,
    required this.workingSessionIds,
    required this.selectedMemberId,
  });

  final List<ChatTabInfo> tabs;
  final int activeTabIndex;
  final Set<String> workingSessionIds;
  final String selectedMemberId;

  static const _listEquality = ListEquality<ChatTabInfo>();
  static const _setEquality = SetEquality<String>();

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is _ShellTabModel &&
            _listEquality.equals(tabs, other.tabs) &&
            activeTabIndex == other.activeTabIndex &&
            _setEquality.equals(workingSessionIds, other.workingSessionIds) &&
            selectedMemberId == other.selectedMemberId;
  }

  @override
  int get hashCode => Object.hash(
    _listEquality.hash(tabs),
    activeTabIndex,
    _setEquality.hash(workingSessionIds),
    selectedMemberId,
  );
}

class _ChatWorkspaceShell extends StatelessWidget {
  const _ChatWorkspaceShell({
    required this.cwd,
    required this.sessionId,
    required this.isPersonalWorkspace,
    required this.workspaceId,
    required this.tabScopeId,
    required this.team,
  });

  final String cwd;
  final String? sessionId;
  final bool isPersonalWorkspace;
  final String workspaceId;
  final String tabScopeId;
  final TeamProfile? team;

  @override
  Widget build(BuildContext context) {
    return BlocSelector<ChatCubit, ChatState, _ShellTabModel>(
      selector: (state) => _ShellTabModel(
        tabs: state.tabs,
        activeTabIndex: state.activeTabIndex,
        workingSessionIds: state.workingSessionIds,
        selectedMemberId: state.selectedMemberId,
      ),
      builder: (context, model) {
        final teamConfig = team;
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
              : 'target: ${context.read<ChatCubit>().selectedMemberName(teamConfig!)} / shell wrapper mode',
          tabs: model.tabs
              .map(
                (t) => TabInfo(
                  id: t.id,
                  title: t.title,
                  working: model.workingSessionIds.contains(t.id),
                  icon: Icons.terminal_rounded,
                  accentColor: Theme.of(context).colorScheme.primary,
                ),
              )
              .toList(),
          activeTabIndex: model.activeTabIndex,
          onTabSelected: (index) => context.read<ChatCubit>().selectTab(index),
          onTabClosed: (index) => context.read<ChatCubit>().closeTab(index),
          onTabCloseOthers: (index) =>
              context.read<ChatCubit>().closeOtherTabs(index),
          onTabCloseRight: (index) =>
              context.read<ChatCubit>().closeRightTabs(index),
          showRightToolsVisibilityToggle: true,
          actions: isPersonalWorkspace
              ? const []
              : _chatActions(context, teamConfig!),
          child: ChatWorkbench(
            workspaceId: workspaceId,
            sessionId: sessionId,
            isPersonalWorkspace: isPersonalWorkspace,
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
