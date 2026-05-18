import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubits/chat_cubit.dart';
import '../cubits/layout_cubit.dart';
import '../cubits/team_cubit.dart';
import '../models/layout_preferences.dart';
import '../models/team_config.dart';
import '../services/platform_utils.dart';
import '../utils/app_keys.dart';
import '../widgets/right_tools_panel.dart';
import 'chat_workbench.dart';
import 'workspace_shell.dart';

class ChatPage extends StatelessWidget {
  const ChatPage({this.sessionId, super.key});

  final String? sessionId;

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
      preferences: preferences,
      panelKey: AppKeys.rightToolsPanel,
      dismissDrawerOnAction: toolsAsDrawer,
    );

    Widget buildShell({VoidCallback? onOpenRightTools, Widget? rightTools}) {
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
        onRightToolsWidthChanged: toolsAsDrawer
            ? null
            : (w) => context.read<LayoutCubit>().setRightToolsWidth(w),
        actions: _chatActions(context, team),
        rightTools: rightTools,
        child: ChatWorkbench(
          sessionId: sessionId,
          onOpenRightTools: onOpenRightTools,
        ),
      );
    }

    if (!toolsAsDrawer) {
      return buildShell(
        rightTools: RightToolsPanel(
          preferences: preferences,
          panelKey: preferences.toolPlacement == ToolPanelPlacement.right
              ? AppKeys.rightToolsPanel
              : AppKeys.bottomToolsPanel,
        ),
      );
    }

    return Scaffold(
      endDrawer: Drawer(
        width: rightToolsDrawerWidth(context, preferences),
        child: SafeArea(child: rightToolsPanel),
      ),
      body: Builder(
        builder: (scaffoldContext) => buildShell(
          onOpenRightTools: () => Scaffold.of(scaffoldContext).openEndDrawer(),
          rightTools: null,
        ),
      ),
    );
  }

  List<Widget> _chatActions(BuildContext context, TeamConfig team) {
    return [
      IconButton.filledTonal(
        key: AppKeys.openTeamLeadButton,
        tooltip: 'Open team-lead',
        onPressed: () {
          final lead = team.members.where((m) => m.name == 'team-lead');
          if (lead.isEmpty) {
            context.read<ChatCubit>().addSystemMessage(
              'FlashskyAI requires a member named team-lead.',
            );
            return;
          }
          unawaited(context.read<ChatCubit>().openMemberTab(team, lead.first));
        },
        icon: const Icon(Icons.person_outline),
      ),
      IconButton.filled(
        key: AppKeys.openTeamButton,
        tooltip: 'Open Team',
        onPressed: () {
          unawaited(context.read<ChatCubit>().launchAllMembers(team));
        },
        icon: const Icon(Icons.groups_outlined),
      ),
    ];
  }
}
