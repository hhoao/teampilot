import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/chat_cubit.dart';
import '../../cubits/mailbox_cubit.dart';
import '../../cubits/member_presence_cubit.dart';
import '../../cubits/launch_profile_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/layout_preferences.dart';
import '../../models/member_instance.dart';
import '../../models/team_config.dart';
import '../../pages/home_workspace/workspace/member_detail_dialog.dart';
import '../../services/cli/member_config/member_config_inspector.dart';
import '../../services/io/system_folder_opener.dart';
import '../../services/git/git_repo_store.dart';
import '../../services/io/workspace_fs_watcher.dart';
import '../../services/storage/app_storage.dart';
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
    this.additionalPaths = const [],
    this.preferences = const LayoutPreferences(),
    this.panelKey = AppKeys.rightToolsPanel,
    this.dismissDrawerOnAction = false,
    this.isPersonalWorkspace = false,
    this.workspaceId,
    super.key,
  });

  final LayoutPreferences preferences;
  final Key panelKey;
  final bool dismissDrawerOnAction;

  /// Solo workspace workbench — hide team members / mailbox tooling.
  final bool isPersonalWorkspace;

  /// Working directory the file tree / git panel operate on. Supplied by the
  /// caller (the workspace context), decoupling the tools from chat-session tab
  /// state.
  final String cwd;

  /// Extra workspace folders (beyond [cwd]) for multi-root file tree / source
  /// control. Empty for single-folder workspaces.
  final List<String> additionalPaths;

  /// Workspace this tools panel belongs to; scopes per-workspace UI state
  /// (selected tool tab). Null on routes without a workspace context.
  final String? workspaceId;

  @override
  State<RightToolsPanel> createState() => _RightToolsPanelState();
}

class _RightToolsPanelState extends State<RightToolsPanel> {
  String? _syncedPresenceTeamId;
  ChatCubit? _chatCubit;
  MemberPresenceCubit? _presenceCubit;

  /// Single recursive watch on the workspace cwd, shared by the file-tree and
  /// source-control panels so they refresh live on disk changes (e.g. files an
  /// agent writes in the terminal) instead of going stale.
  WorkspaceFsWatcher? _fsWatcher;

  /// Last-seen set of in-turn sessions; a session leaving it (turn end) is the
  /// activity signal we use to refresh on backends without a native FS watch
  /// (SSH/Android), where disk events never arrive.
  Set<String> _prevWorkingSessionIds = const {};

  /// App-level git status cache. The source-control panel reads warm state from
  /// here; this panel (which outlives tool-tab switches) keeps it fresh so the
  /// tab opens instantly. Null in harnesses without the provider.
  GitRepoStore? _gitStore;
  StreamSubscription<void>? _gitWatchSub;
  Timer? _gitPollTimer;
  static const _gitPollInterval = Duration(seconds: 15);

  @override
  void initState() {
    super.initState();
    _rebuildWatcher();
  }

  /// Workspace folders for the file tree / source control panels: the primary
  /// [RightToolsPanel.cwd] first, then any [RightToolsPanel.additionalPaths]
  /// (deduped, empties dropped).
  List<String> get _workspaceRoots {
    final roots = <String>[];
    for (final path in [widget.cwd, ...widget.additionalPaths]) {
      if (path.isNotEmpty && !roots.contains(path)) roots.add(path);
    }
    return roots;
  }

  void _rebuildWatcher() {
    _fsWatcher?.dispose();
    _fsWatcher = widget.cwd.isEmpty
        ? null
        : WorkspaceFsWatcher(fs: AppStorage.fs, root: widget.cwd);
  }

  @override
  void didUpdateWidget(covariant RightToolsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.cwd != oldWidget.cwd) {
      _rebuildWatcher();
    }
    if (widget.cwd != oldWidget.cwd ||
        !listEquals(widget.additionalPaths, oldWidget.additionalPaths) ||
        widget.preferences.gitVisible != oldWidget.preferences.gitVisible) {
      _setupGitPolling();
    }
  }

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
    final gitStore = context.read<GitRepoStore?>();
    if (!identical(_gitStore, gitStore)) {
      _gitStore = gitStore;
      _setupGitPolling();
    }
  }

  /// Warms the workspace's git repos and keeps them fresh while the git tool is
  /// enabled, so opening the source-control tab shows up-to-date state with no
  /// per-open subprocess wait. Uses the disk watcher when available, else a
  /// periodic poll (SSH/Android).
  ///
  /// Deliberate perf tradeoff: this polls while the git tool is *enabled*
  /// (`gitVisible`), not only while its tab is selected — so multi-root badges
  /// stay live and reopening is instant. The cost is bounded: each watcher
  /// burst / tick fans out to [GitRepoStore.refreshAll], and every per-root
  /// [GitCubit.refresh] coalesces (one in-flight + one trailing run), so status
  /// subprocesses never pile up regardless of event rate. If profiling ever
  /// flags this, narrow it to the active root + a refreshAll on tab open.
  void _setupGitPolling() {
    _gitWatchSub?.cancel();
    _gitWatchSub = null;
    _gitPollTimer?.cancel();
    _gitPollTimer = null;

    final store = _gitStore;
    if (store == null || !widget.preferences.gitVisible) return;

    _warmGit();
    final watcher = _fsWatcher;
    if (watcher?.isSupported ?? false) {
      _gitWatchSub = watcher!.onChanged.listen((_) => _warmGit());
    } else {
      _gitPollTimer = Timer.periodic(_gitPollInterval, (_) => _warmGit());
    }
  }

  void _warmGit() => _gitStore?.refreshAll(_workspaceRoots);

  /// Pokes the watcher when any session leaves the working set (a turn ended,
  /// so the agent has likely just written files). Cheap no-op on watch-capable
  /// backends; the real change path for SSH/Android where no disk events fire.
  void _pokeOnTurnEnd(Set<String> working) {
    final ended = _prevWorkingSessionIds.difference(working).isNotEmpty;
    _prevWorkingSessionIds = working;
    if (ended) _fsWatcher?.poke();
  }

  @override
  void dispose() {
    _gitWatchSub?.cancel();
    _gitPollTimer?.cancel();
    _fsWatcher?.dispose();
    _presenceCubit?.detachPresenceUi(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final teamCubit = context.watch<LaunchProfileCubit>();
    final chatCubit = context.watch<ChatCubit>();
    _pokeOnTurnEnd(chatCubit.state.workingSessionIds);
    final team = teamCubit.state.selectedTeam;
    final teamId = team?.id;
    if (!widget.isPersonalWorkspace && teamId != _syncedPresenceTeamId) {
      _syncedPresenceTeamId = teamId;
      final presenceCubit = _presenceCubit;
      final teamSnapshot = team;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        presenceCubit?.syncPresenceTeam(teamSnapshot);
      });
    }
    if (!widget.isPersonalWorkspace && team == null) {
      return const SizedBox.shrink();
    }

    final runtimeMembers = team == null
        ? const <TeamMemberConfig>[]
        : runtimeRosterMembers(team);
    final members = [...runtimeMembers]
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

    // Mailbox is an optional, mixed-mode-only view; tolerate its cubit being
    // absent (e.g. lightweight test harnesses) rather than crashing the shell.
    final mailboxCubit = context.watch<MailboxCubit?>();
    final mailboxState = mailboxCubit?.state ?? const MailboxState();
    final showMailbox =
        !widget.isPersonalWorkspace &&
        team != null &&
        mailboxCubit != null &&
        team.teamMode == TeamMode.mixed &&
        chatCubit.activeTab?.teamBus != null;

    // Board is mixed-mode-only and consumes the same TeamBus as mailbox; it
    // shares mailbox's gate (the unread badge is mailbox-specific and doesn't
    // affect whether the bus exists). Also gated on the layout preference.
    final showBoard = showMailbox && widget.preferences.boardVisible;

    final views = <ToolView>[];
    if (!widget.isPersonalWorkspace &&
        widget.preferences.membersVisible &&
        team != null) {
      views.add(
        ToolView(
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
              final activeTab = chatCubit.activeTab;
              final workspaceId =
                  widget.workspaceId ?? activeTab?.workspaceId ?? '';
              final sessionId = activeTab?.info.id ?? '';
              unawaited(
                showMemberDetailDialog(
                  context,
                  workspaceId: workspaceId,
                  sessionId: sessionId,
                  team: team,
                  member: member,
                ),
              );
              maybeDismissDrawer();
            },
            onOpenConfigDir: (id) {
              final member = runtimeMembers.firstWhere((m) => m.id == id);
              final activeTab = chatCubit.activeTab;
              final workspaceId =
                  widget.workspaceId ?? activeTab?.workspaceId ?? '';
              final sessionId = activeTab?.info.id ?? '';
              unawaited(() async {
                final detail = await MemberConfigInspector().inspect(
                  workspaceId: workspaceId,
                  sessionId: sessionId,
                  team: team,
                  member: member,
                );
                if (detail.resolvedDir.isNotEmpty) {
                  await SystemFolderOpener().reveal(detail.resolvedDir);
                }
              }());
              maybeDismissDrawer();
            },
          ),
        ),
      );
    }
    if (widget.preferences.fileTreeVisible) {
      views.add(
        ToolView(
          icon: Icons.folder_outlined,
          label: context.l10n.fileTree,
          child: FileTreePanel(roots: _workspaceRoots, watcher: _fsWatcher),
        ),
      );
    }
    if (widget.preferences.gitVisible) {
      views.add(
        ToolView(
          icon: Icons.account_tree_outlined,
          label: context.l10n.sourceControl,
          child: GitSourceControlPanel(roots: _workspaceRoots),
        ),
      );
    }
    if (showMailbox) {
      views.add(
        ToolView(
          icon: Icons.mail_outline,
          label: context.l10n.mailbox,
          badgeCount: mailboxState.totalUnread,
          child: MailboxPanel(team: team, cwd: widget.cwd),
        ),
      );
    }
    if (showBoard) {
      views.add(
        ToolView(
          icon: Icons.view_kanban_outlined,
          label: context.l10n.board,
          child: BoardPanel(team: team, cwd: widget.cwd),
        ),
      );
    }
    return Container(
      key: widget.panelKey,
      child: TabbedPanel(views: views, scopeId: widget.workspaceId),
    );
  }
}
