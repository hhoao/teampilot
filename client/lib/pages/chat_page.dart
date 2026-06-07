import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubits/chat_cubit.dart';
import '../cubits/editor_cubit.dart';
import '../cubits/layout_cubit.dart';
import '../cubits/team_cubit.dart';
import '../l10n/l10n_extensions.dart';
import '../models/layout_preferences.dart';
import '../models/team_config.dart';
import '../services/app/platform_utils.dart';
import '../utils/app_keys.dart';
import '../utils/debounce/debounce.dart';
import '../widgets/right_tools/right_tools_panel.dart';
import 'chat/team_config_incomplete_dialog.dart';
import 'chat_workbench.dart';
import 'workspace_shell/workspace_shell.dart';

class ChatPage extends StatelessWidget {
  const ChatPage({
    required this.cwd,
    this.sessionId,
    this.isPersonalProject = false,
    this.projectId,
    super.key,
  });

  final String? sessionId;

  /// Working directory the file tree / git tools operate on, supplied by the
  /// caller (e.g. project path on the v2 project page). [ChatPage] never
  /// derives it from session state.
  final String cwd;

  /// When true, the embedded workbench runs without a selected [TeamConfig].
  final bool isPersonalProject;

  /// Owning project id; scopes the workspace terminal + right-tools selection.
  /// Null on chat routes without a project context.
  final String? projectId;

  @override
  Widget build(BuildContext context) {
    if (isPersonalProject) {
      return _PersonalChatPage(cwd: cwd, sessionId: sessionId, projectId: projectId);
    }
    return _TeamChatPage(cwd: cwd, sessionId: sessionId, projectId: projectId);
  }
}

class _PersonalChatPage extends StatelessWidget {
  const _PersonalChatPage({required this.cwd, this.sessionId, this.projectId});

  final String cwd;
  final String? sessionId;
  final String? projectId;

  @override
  Widget build(BuildContext context) {
    final chatCubit = context.watch<ChatCubit>();
    final preferences = context.watch<LayoutCubit>().state.preferences;
    return _ChatPageBody(
      cwd: cwd,
      sessionId: sessionId,
      isPersonalProject: true,
      chatCubit: chatCubit,
      preferences: preferences,
      team: null,
      projectId: projectId,
    );
  }
}

class _TeamChatPage extends StatelessWidget {
  const _TeamChatPage({required this.cwd, this.sessionId, this.projectId});

  final String cwd;
  final String? sessionId;
  final String? projectId;

  @override
  Widget build(BuildContext context) {
    final chatCubit = context.watch<ChatCubit>();
    final preferences = context.watch<LayoutCubit>().state.preferences;
    final team = context.watch<TeamCubit>().state.selectedTeam;

    if (team == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return _ChatPageBody(
      cwd: cwd,
      sessionId: sessionId,
      isPersonalProject: false,
      chatCubit: chatCubit,
      preferences: preferences,
      team: team,
      projectId: projectId,
    );
  }
}

class _ChatPageBody extends StatelessWidget {
  const _ChatPageBody({
    required this.cwd,
    required this.sessionId,
    required this.isPersonalProject,
    required this.chatCubit,
    required this.preferences,
    required this.team,
    required this.projectId,
  });

  final String cwd;
  final String? sessionId;
  final bool isPersonalProject;
  final ChatCubit chatCubit;
  final LayoutPreferences preferences;
  final TeamConfig? team;
  final String? projectId;

  @override
  Widget build(BuildContext context) {
    final toolsAsDrawer = useRightToolsAsDrawer(context);
    final rightToolsPanel = RightToolsPanel(
      cwd: cwd,
      preferences: preferences,
      panelKey: AppKeys.rightToolsPanel,
      dismissDrawerOnAction: toolsAsDrawer,
      isPersonalProject: isPersonalProject,
      projectId: projectId,
    );
    Widget buildShell({Widget? rightTools}) {
      return WorkspaceShell(
        workspaceTerminalWorkingDirectory: cwd,
        workspaceProjectId: projectId,
        showHeader: false,
        breadcrumb: isPersonalProject
            ? 'Personal / Chat / Shell chat workbench'
            : '${team!.name} / Chat / Shell chat workbench',
        title: 'Shell chat workbench',
        subtitle: isPersonalProject
            ? 'personal project / shell wrapper mode'
            : 'target: ${chatCubit.selectedMemberName(team!)} / shell wrapper mode',
        tabs: chatCubit.state.tabs
            .map((t) => TabInfo(id: t.id, title: t.title))
            .toList(),
        activeTabIndex: chatCubit.state.activeTabIndex,
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
            : _chatActions(context, team!),
        rightTools: rightTools,
        child: ChatWorkbench(
          sessionId: sessionId,
          isPersonalProject: isPersonalProject,
        ),
      );
    }

    if (!toolsAsDrawer) {
      return _chatLaunchListener(
        context,
        buildShell(
          rightTools: preferences.rightToolsVisible
              ? RightToolsPanel(
                  cwd: cwd,
                  preferences: preferences,
                  isPersonalProject: isPersonalProject,
                  projectId: projectId,
                  panelKey:
                      preferences.toolPlacement == ToolPanelPlacement.right
                      ? AppKeys.rightToolsPanel
                      : AppKeys.bottomToolsPanel,
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
        body: buildShell(rightTools: null),
      ),
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
        icon: const Icon(Icons.person_outline),
      ),
      IconButton.filled(
        key: AppKeys.openTeamButton,
        tooltip: 'Open Team',
        onPressed: throttledAsync(
          'chat_launch_all_members',
          () => context.read<ChatCubit>().launchAllMembers(team),
        ),
        icon: const Icon(Icons.groups_outlined),
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
