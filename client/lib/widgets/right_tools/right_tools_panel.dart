import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/chat_cubit.dart';
import '../../cubits/mailbox_cubit.dart';
import '../../cubits/member_presence_cubit.dart';
import '../../cubits/team_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/layout_preferences.dart';
import '../../models/team_config.dart';
import '../../theme/workspace_surface_layers.dart';
import '../../utils/app_keys.dart';
import '../../utils/debounce/debounce.dart';
import '../../utils/team_member_naming.dart';
import '../git/git_source_control_panel.dart';
import 'file_tree_panel.dart';
import 'mailbox_panel.dart';
import 'members_panel.dart';
import 'stacked_panel.dart';
import 'tabbed_panel.dart';
import 'tool_view.dart';

class RightToolsPanel extends StatefulWidget {
  const RightToolsPanel({
    required this.cwd,
    this.preferences = const LayoutPreferences(),
    this.panelKey = AppKeys.rightToolsPanel,
    this.dismissDrawerOnAction = false,
    super.key,
  });

  final LayoutPreferences preferences;
  final Key panelKey;
  final bool dismissDrawerOnAction;

  /// Working directory the file tree / git panel operate on. Supplied by the
  /// caller (the project context), decoupling the tools from chat-session tab
  /// state.
  final String cwd;

  @override
  State<RightToolsPanel> createState() => _RightToolsPanelState();
}

class _RightToolsPanelState extends State<RightToolsPanel> {
  String? _syncedPresenceTeamId;
  ChatCubit? _chatCubit;
  MemberPresenceCubit? _presenceCubit;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final chatCubit = context.read<ChatCubit>();
    final presenceCubit = context.read<MemberPresenceCubit>();
    if (!identical(_chatCubit, chatCubit)) {
      _presenceCubit?.detachPresenceUi();
      _chatCubit = chatCubit;
      _presenceCubit = presenceCubit;
      presenceCubit.attachPresenceUi();
    }
  }

  @override
  void dispose() {
    _presenceCubit?.detachPresenceUi();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final teamCubit = context.watch<TeamCubit>();
    final chatCubit = context.watch<ChatCubit>();
    final team = teamCubit.state.selectedTeam;
    final teamId = team?.id;
    if (teamId != _syncedPresenceTeamId) {
      _syncedPresenceTeamId = teamId;
      final presenceCubit = _presenceCubit;
      final teamSnapshot = team;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        presenceCubit?.syncPresenceTeam(teamSnapshot);
      });
    }
    if (team == null) return const SizedBox.shrink();

    final members = [...team.members]
      ..sort((a, b) {
        if (TeamMemberNaming.isTeamLead(a)) return -1;
        if (TeamMemberNaming.isTeamLead(b)) return 1;
        return a.name.compareTo(b.name);
      });
    void maybeDismissDrawer() {
      if (widget.dismissDrawerOnAction) {
        Navigator.of(context).maybePop();
      }
    }

    final mailboxState = context.watch<MailboxCubit>().state;
    final showMailbox =
        team.teamMode == TeamMode.mixed && chatCubit.activeTab?.teamBus != null;

    final views = <ToolView>[
      if (widget.preferences.membersVisible)
        ToolView(
          icon: Icons.groups_outlined,
          label: context.l10n.members,
          child: MembersPanel(
            teamCli: team.cli,
            members: members,
            memberPresence:
                context.watch<MemberPresenceCubit>().state.presence,
            selectedMemberId: chatCubit.state.selectedMemberId,
            onSelected: (id) {
              final member = team.members.firstWhere((m) => m.id == id);
              final cubit = _chatCubit;
              if (cubit == null) return;
              unawaited(
                cubit.openMemberTab(team, member, workspaceCwd: widget.cwd),
              );
              maybeDismissDrawer();
            },
            onOpen: (id) {
              final member = team.members.firstWhere((m) => m.id == id);
              final cubit = _chatCubit;
              if (cubit == null) return;
              unawaited(
                cubit.openMemberTab(team, member, workspaceCwd: widget.cwd),
              );
              maybeDismissDrawer();
            },
            onLaunchAll: throttledAsync('right_tools_launch_all', () async {
              final cubit = _chatCubit;
              if (cubit == null) return;
              await cubit.launchAllMembers(team, workspaceCwd: widget.cwd);
              maybeDismissDrawer();
            }),
          ),
        ),
      if (widget.preferences.fileTreeVisible)
        ToolView(
          icon: Icons.folder_outlined,
          label: context.l10n.fileTree,
          child: FileTreePanel(team: team, cwd: widget.cwd),
        ),
      if (widget.preferences.gitVisible)
        ToolView(
          icon: Icons.account_tree_outlined,
          label: context.l10n.sourceControl,
          child: GitSourceControlPanel(cwd: widget.cwd),
        ),
      if (showMailbox)
        ToolView(
          icon: Icons.mail_outline,
          label: context.l10n.mailbox,
          badgeCount: mailboxState.totalUnread,
          child: MailboxPanel(team: team, cwd: widget.cwd),
        ),
    ];
    return Container(
      key: widget.panelKey,
      color: cs.workspaceSubtleSurface,
      child: widget.preferences.toolsArrangement == ToolsArrangement.tabs
          ? TabbedPanel(views: views)
          : StackedPanel(views: views),
    );
  }
}
