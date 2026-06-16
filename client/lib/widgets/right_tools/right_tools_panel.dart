import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/chat_cubit.dart';
import '../../cubits/mailbox_cubit.dart';
import '../../cubits/member_presence_cubit.dart';
import '../../cubits/team_cubit.dart';
import '../../cubits/workspace_tools_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/layout_preferences.dart';
import '../../models/member_instance.dart';
import '../../models/team_config.dart';
import '../../pages/home_workspace/project/member_detail_dialog.dart';
import '../../services/cli/member_config/member_config_inspector.dart';
import '../../services/io/system_folder_opener.dart';
import '../../utils/app_keys.dart';
import '../../utils/debounce/debounce.dart';
import '../../utils/team_member_naming.dart';
import '../git/git_source_control_panel.dart';
import 'file_tree_panel.dart';
import 'board_panel.dart';
import 'mailbox_panel.dart';
import 'members_panel.dart';
import 'tabbed_panel.dart';
import 'tool_view.dart';

class RightToolsPanel extends StatefulWidget {
  const RightToolsPanel({
    required this.cwd,
    this.preferences = const LayoutPreferences(),
    this.panelKey = AppKeys.rightToolsPanel,
    this.dismissDrawerOnAction = false,
    this.isPersonalProject = false,
    this.projectId,
    super.key,
  });

  final LayoutPreferences preferences;
  final Key panelKey;
  final bool dismissDrawerOnAction;

  /// Solo project workbench — hide team members / mailbox tooling.
  final bool isPersonalProject;

  /// Working directory the file tree / git panel operate on. Supplied by the
  /// caller (the project context), decoupling the tools from chat-session tab
  /// state.
  final String cwd;

  /// Project this tools panel belongs to; scopes per-project UI state
  /// (selected tool tab). Null on routes without a project context.
  final String? projectId;

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
      _presenceCubit?.detachPresenceUi(this);
      _chatCubit = chatCubit;
      _presenceCubit = presenceCubit;
      presenceCubit.attachPresenceUi(this);
    }
  }

  @override
  void dispose() {
    _presenceCubit?.detachPresenceUi(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final teamCubit = context.watch<TeamCubit>();
    final chatCubit = context.watch<ChatCubit>();
    final team = teamCubit.state.selectedTeam;
    final teamId = team?.id;
    if (!widget.isPersonalProject && teamId != _syncedPresenceTeamId) {
      _syncedPresenceTeamId = teamId;
      final presenceCubit = _presenceCubit;
      final teamSnapshot = team;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        presenceCubit?.syncPresenceTeam(teamSnapshot);
      });
    }
    if (!widget.isPersonalProject && team == null) {
      return const SizedBox.shrink();
    }

    final runtimeMembers =
        team == null ? const <TeamMemberConfig>[] : runtimeRosterMembers(team);
    final members = [...runtimeMembers]..sort((a, b) {
      if (TeamMemberNaming.isTeamLead(a)) return -1;
      if (TeamMemberNaming.isTeamLead(b)) return 1;
      return a.name.compareTo(b.name);
    });
    void maybeDismissDrawer() {
      if (widget.dismissDrawerOnAction) {
        Navigator.of(context).maybePop();
      }
    }

    // Mailbox is an optional, mixed-mode-only view; tolerate its cubit being
    // absent (e.g. lightweight test harnesses) rather than crashing the shell.
    final mailboxCubit = context.watch<MailboxCubit?>();
    final mailboxState = mailboxCubit?.state ?? const MailboxState();
    final showMailbox =
        !widget.isPersonalProject &&
        team != null &&
        mailboxCubit != null &&
        team.teamMode == TeamMode.mixed &&
        chatCubit.activeTab?.teamBus != null;

    // Board is mixed-mode-only and consumes the same TeamBus as mailbox; it
    // shares mailbox's gate (the unread badge is mailbox-specific and doesn't
    // affect whether the bus exists). Also gated on the layout preference.
    final showBoard = showMailbox && widget.preferences.boardVisible;

    // Rebuild when the user switches tool tabs so that the active tool can
    // enable/disable auto-refresh behaviour.
    context.watch<WorkspaceToolsCubit>();
    final selectedIndex = widget.projectId != null
        ? context.read<WorkspaceToolsCubit>().selectedIndexFor(widget.projectId!)
        : 0;

    final views = <ToolView>[];
    if (!widget.isPersonalProject &&
        widget.preferences.membersVisible &&
        team != null) {
      views.add(ToolView(
        icon: Icons.groups_outlined,
        label: context.l10n.members,
        child: MembersPanel(
          team: team,
          members: members,
          memberPresence: context.watch<MemberPresenceCubit>().state.presence,
          selectedMemberId: chatCubit.state.selectedMemberId,
          onSelected: (id) {
            final member = runtimeMembers.firstWhere((m) => m.id == id);
            final cubit = _chatCubit;
            if (cubit == null) return;
            unawaited(
              cubit.openMemberTab(team, member, workspaceCwd: widget.cwd),
            );
            maybeDismissDrawer();
          },
          onOpen: (id) {
            final member = runtimeMembers.firstWhere((m) => m.id == id);
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
          canViewDetail: chatCubit.activeTab != null,
          onViewDetail: (id) {
            final member = runtimeMembers.firstWhere((m) => m.id == id);
            final cliTeamName = chatCubit.activeTab?.cliTeamName ?? '';
            unawaited(showMemberDetailDialog(
              context,
              team: team,
              member: member,
              cliTeamName: cliTeamName,
            ));
            maybeDismissDrawer();
          },
          onOpenConfigDir: (id) {
            final member = runtimeMembers.firstWhere((m) => m.id == id);
            final cliTeamName = chatCubit.activeTab?.cliTeamName ?? '';
            unawaited(() async {
              final detail = await MemberConfigInspector().inspect(
                team: team,
                member: member,
                cliTeamName: cliTeamName,
              );
              if (detail.resolvedDir.isNotEmpty) {
                await SystemFolderOpener().reveal(detail.resolvedDir);
              }
            }());
            maybeDismissDrawer();
          },
        ),
      ));
    }
    if (widget.preferences.fileTreeVisible) {
      views.add(ToolView(
        icon: Icons.folder_outlined,
        label: context.l10n.fileTree,
        child: FileTreePanel(cwd: widget.cwd),
      ));
    }
    if (widget.preferences.gitVisible) {
      final isGitActive = selectedIndex == views.length;
      views.add(ToolView(
        icon: Icons.account_tree_outlined,
        label: context.l10n.sourceControl,
        child: GitSourceControlPanel(cwd: widget.cwd, isActive: isGitActive),
      ));
    }
    if (showMailbox) {
      views.add(ToolView(
        icon: Icons.mail_outline,
        label: context.l10n.mailbox,
        badgeCount: mailboxState.totalUnread,
        child: MailboxPanel(team: team, cwd: widget.cwd),
      ));
    }
    if (showBoard) {
      views.add(ToolView(
        icon: Icons.view_kanban_outlined,
        label: context.l10n.board,
        child: BoardPanel(team: team, cwd: widget.cwd),
      ));
    }
    return Container(
      key: widget.panelKey,
      child: TabbedPanel(views: views, scopeId: widget.projectId),
    );
  }
}
