import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubits/chat_cubit.dart';
import '../cubits/layout_cubit.dart';
import '../cubits/team_cubit.dart';
import '../l10n/app_localizations.dart';
import '../models/layout_preferences.dart';
import '../repositories/session_repository.dart';
import '../utils/app_keys.dart';
import '../widgets/right_tools_panel.dart';
import 'chat_workbench.dart';
import 'workspace_shell.dart';

class ChatPage extends StatelessWidget {
  const ChatPage({this.sessionId, super.key});

  final String? sessionId;

  static void _showTabRenameDialog(
    BuildContext context,
    String tabId,
    String title,
  ) {
    final l10n = context.l10n;
    final controller = TextEditingController(text: title);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.renameConversationTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: l10n.conversationName,
          ),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              context.read<ChatCubit>().renameSession(
                const SessionRepository(),
                tabId,
                value.trim(),
              );
            }
            Navigator.of(ctx).pop();
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) {
                context.read<ChatCubit>().renameSession(
                  const SessionRepository(),
                  tabId,
                  value,
                );
              }
              Navigator.of(ctx).pop();
            },
            child: Text(l10n.save),
          ),
        ],
      ),
    );
  }

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
      onTabRenamed: (index) {
        final tabs = context.read<ChatCubit>().state.tabs;
        if (index >= tabs.length) return;
        final tab = tabs[index];
        _showTabRenameDialog(context, tab.id, tab.title);
      },
      layoutPreferences: preferences,
      onRightToolsWidthChanged:
          (w) => context.read<LayoutCubit>().setRightToolsWidth(w),
      actions: [
        IconButton.filledTonal(
          key: AppKeys.openTeamLeadButton,
          tooltip: 'Open team-lead',
          onPressed: () {
            final lead =
                team.members.where((m) => m.name == 'team-lead');
            if (lead.isEmpty) {
              context.read<ChatCubit>().addSystemMessage(
                  'FlashskyAI requires a member named team-lead.');
              return;
            }
            context
                .read<ChatCubit>()
                .openMemberTab(team, lead.first);
          },
          icon: const Icon(Icons.person_outline),
        ),
        IconButton.filled(
          key: AppKeys.openTeamButton,
          tooltip: 'Open Team',
          onPressed: () {
            context.read<ChatCubit>().launchAllMembers(team);
          },
          icon: const Icon(Icons.groups_outlined),
        ),
      ],
      rightTools: RightToolsPanel(
        preferences: preferences,
        panelKey: preferences.toolPlacement == ToolPanelPlacement.right
            ? AppKeys.rightToolsPanel
            : AppKeys.bottomToolsPanel,
      ),
      child: ChatWorkbench(sessionId: sessionId),
    );
  }
}
