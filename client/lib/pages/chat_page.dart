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
import '../widgets/right_tools_panel.dart';
import 'chat_workbench.dart';
import 'workspace_shell.dart';

class ChatPage extends StatelessWidget {
  const ChatPage({required this.cwd, this.sessionId, super.key});

  final String? sessionId;

  /// Working directory the file tree / git tools operate on, supplied by the
  /// caller's context (project path for the v2 project page; active-session
  /// cwd for the chat routes). [ChatPage] never derives it from session state.
  final String cwd;

  @override
  Widget build(BuildContext context) {
    final teamCubit = context.watch<TeamCubit>();
    final chatCubit = context.watch<ChatCubit>();
    final layoutCubit = context.watch<LayoutCubit>();
    final preferences = layoutCubit.state.preferences;
    final team = teamCubit.state.selectedTeam;

    if (team == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final toolsAsDrawer = useRightToolsAsDrawer(context);
    final rightToolsPanel = RightToolsPanel(
      cwd: cwd,
      preferences: preferences,
      panelKey: AppKeys.rightToolsPanel,
      dismissDrawerOnAction: toolsAsDrawer,
    );
    final activeChatAnimationId =
        chatCubit.state.activeTabIndex >= 0 &&
            chatCubit.state.activeTabIndex < chatCubit.state.tabs.length
        ? chatCubit.state.tabs[chatCubit.state.activeTabIndex].id
        : sessionId ?? 'empty';

    Widget buildShell({Widget? rightTools}) {
      return WorkspaceShell(
        showHeader: false,
        breadcrumb: '${team.name} / Chat / Shell chat workbench',
        title: 'Shell chat workbench',
        subtitle:
            'target: ${chatCubit.selectedMemberName(team)} / shell wrapper mode',
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
        actions: _chatActions(context, team),
        rightTools: rightTools,
        childAnimationKey: ValueKey(
          'chat-workspace-body-$activeChatAnimationId',
        ),
        child: ChatWorkbench(sessionId: sessionId),
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
                  panelKey: preferences.toolPlacement == ToolPanelPlacement.right
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
        ScaffoldMessenger.of(listenerContext).showSnackBar(
          SnackBar(content: Text(message)),
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
          final message =
              listenerContext.l10n.editorSnackbarMessage(code);
          ScaffoldMessenger.of(listenerContext).showSnackBar(
            SnackBar(content: Text(message)),
          );
          listenerContext.read<EditorCubit>().clearSnackbarMessage();
        },
        child: child,
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

/// Chat route entry that scopes the tools to the active session's cwd. Keeps
/// the "follow the active session" behavior out of [ChatPage] itself, which
/// only renders the cwd it is given.
class ActiveSessionChatPage extends StatelessWidget {
  const ActiveSessionChatPage({this.sessionId, super.key});

  final String? sessionId;

  @override
  Widget build(BuildContext context) {
    final cwd = context.select<ChatCubit, String>((c) => c.state.activeCwd);
    return ChatPage(sessionId: sessionId, cwd: cwd);
  }
}
