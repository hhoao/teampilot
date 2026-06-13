import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

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
import 'team_config_incomplete_dialog.dart';

class ChatPageShell extends StatelessWidget {
  const ChatPageShell({
    required this.cwd,
    required this.isPersonalProject,
    required this.projectId,
    required this.team,
    this.sessionId,
    super.key,
  });

  final String cwd;
  final String? sessionId;
  final bool isPersonalProject;
  final String? projectId;
  final TeamConfig? team;

  @override
  Widget build(BuildContext context) {
    final preferences = context.select<LayoutCubit, LayoutPreferences>(
      (c) => c.state.preferences,
    );
    final toolsAsDrawer = useRightToolsAsDrawer(context);
    final rightToolsPanel = RightToolsPanel(
      cwd: cwd,
      preferences: preferences,
      panelKey: AppKeys.rightToolsPanel,
      dismissDrawerOnAction: toolsAsDrawer,
      isPersonalProject: isPersonalProject,
      projectId: projectId,
    );

    Widget buildWorkspace({Widget? rightTools}) {
      return _ChatWorkspaceShell(
        cwd: cwd,
        sessionId: sessionId,
        isPersonalProject: isPersonalProject,
        projectId: projectId,
        team: team,
        preferences: preferences,
        toolsAsDrawer: toolsAsDrawer,
        rightTools: rightTools,
      );
    }

    if (!toolsAsDrawer) {
      return _chatLaunchListener(
        context,
        buildWorkspace(
          rightTools: preferences.rightToolsVisible
              ? RightToolsPanel(
                  cwd: cwd,
                  preferences: preferences,
                  isPersonalProject: isPersonalProject,
                  projectId: projectId,
                  panelKey: AppKeys.rightToolsPanel,
                )
              : null,
        ),
      );
    }

    return _chatLaunchListener(
      context,
      Scaffold(
        endDrawer: preferences.rightToolsVisible
            ? Drawer(
                width: rightToolsDrawerWidth(context, preferences),
                child: SafeArea(child: rightToolsPanel),
              )
            : null,
        body: buildWorkspace(rightTools: null),
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
    required this.isPersonalProject,
    required this.projectId,
    required this.team,
    required this.preferences,
    required this.toolsAsDrawer,
    required this.rightTools,
  });

  final String cwd;
  final String? sessionId;
  final bool isPersonalProject;
  final String? projectId;
  final TeamConfig? team;
  final LayoutPreferences preferences;
  final bool toolsAsDrawer;
  final Widget? rightTools;

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
          workspaceProjectId: projectId,
          showHeader: false,
          breadcrumb: isPersonalProject
              ? 'Personal / Chat / Shell chat workbench'
              : '${teamConfig!.name} / Chat / Shell chat workbench',
          title: 'Shell chat workbench',
          subtitle: isPersonalProject
              ? 'personal project / shell wrapper mode'
              : 'target: ${context.read<ChatCubit>().selectedMemberName(teamConfig!)} / shell wrapper mode',
          tabs: model.tabs
              .map(
                (t) => TabInfo(
                  id: t.id,
                  title: t.title,
                  working: model.workingSessionIds.contains(t.id),
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
          layoutPreferences: preferences,
          showRightToolsVisibilityToggle: true,
          onRightToolsWidthChanged: toolsAsDrawer
              ? null
              : (w) => context.read<LayoutCubit>().setRightToolsWidth(w),
          actions: isPersonalProject
              ? const []
              : _chatActions(context, teamConfig!),
          rightTools: rightTools,
          child: ChatWorkbench(
            sessionId: sessionId,
            isPersonalProject: isPersonalProject,
          ),
        );
      },
    );
  }

  List<Widget> _chatActions(BuildContext context, TeamConfig team) {
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
          unawaited(context.read<ChatCubit>().openMemberTab(team, lead.first));
        }),
        icon: Icon(Icons.person_outline),
      ),
      IconButton.filled(
        key: AppKeys.openTeamButton,
        tooltip: 'Open Team',
        onPressed: throttledAsync(
          'chat_launch_all_members',
          () => context.read<ChatCubit>().launchAllMembers(team),
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
      ScaffoldMessenger.of(
        listenerContext,
      ).showSnackBar(SnackBar(content: Text(message)));
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
        ScaffoldMessenger.of(
          listenerContext,
        ).showSnackBar(SnackBar(content: Text(message)));
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
