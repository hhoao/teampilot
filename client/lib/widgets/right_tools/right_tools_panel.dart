import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/chat_cubit.dart';
import '../../cubits/file_tree_cubit.dart';
import '../../cubits/mailbox_cubit.dart';
import '../../cubits/member_presence_cubit.dart';
import '../../cubits/launch_profile_cubit.dart';
import '../../cubits/worktree_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../theme/app_text_styles.dart';
import '../../models/layout_preferences.dart';
import '../../models/member_instance.dart';
import '../../models/team_config.dart';
import '../../models/workspace_topology.dart';
import '../../pages/home_workspace/workspace/member_detail_dialog.dart';
import '../../pages/home_workspace/workspace/member_folder_assignment_dialog.dart';
import '../../services/cli/member_config/member_config_inspector.dart';
import '../../services/io/system_folder_opener.dart';
import '../../services/file_tree/workspace_file_tree_store.dart';
import '../../services/git/git_repo_store.dart';
import '../../services/io/workspace_fs_watcher.dart';
import '../../services/storage/app_storage.dart';
import '../../utils/app_keys.dart';
import '../../utils/debounce/debounce.dart';
import '../../utils/team_member_naming.dart';
import '../../utils/workspace_path_utils.dart';
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
    required this.workspaceId,
    this.toolsScopeId,
    this.additionalPaths = const [],
    this.preferences = const LayoutPreferences(),
    this.panelKey = AppKeys.rightToolsPanel,
    this.dismissDrawerOnAction = false,
    this.isPersonalWorkspace = false,
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

  /// Workspace this tools panel belongs to; scopes [WorkspaceFileTreeStore] retention.
  final String workspaceId;

  /// Per title-bar tab scope for tool-tab selection; defaults to [workspaceId].
  final String? toolsScopeId;

  String get _toolsScopeId => toolsScopeId ?? workspaceId;

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

  FileTreeCubit get _fileTreeCubit =>
      context.read<WorkspaceFileTreeStore>().cubitFor(widget.workspaceId);
  StreamSubscription<Set<String>>? _diskWatchSub;
  Timer? _diskPollTimer;
  static const _diskPollInterval = Duration(seconds: 15);

  @override
  void initState() {
    super.initState();
    _rebuildWatcher();
    unawaited(_fileTreeCubit.setRoots(_workspaceRoots));
    _setupDiskRefresh();
  }

  /// Workspace folders for the file tree / source control panels: the primary
  /// [RightToolsPanel.cwd] first, then any [RightToolsPanel.additionalPaths]
  /// (deduped, empties dropped).
  List<String> get _workspaceRoots {
    final ctx = AppStorage.fs.pathContext;
    final roots = <String>[];
    for (final path in [widget.cwd, ...widget.additionalPaths]) {
      if (path.isEmpty) continue;
      final normalized = ctx.normalize(path);
      if (!roots.contains(normalized)) roots.add(normalized);
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
    final rootsChanged =
        widget.cwd != oldWidget.cwd ||
        !listEquals(widget.additionalPaths, oldWidget.additionalPaths);
    if (rootsChanged ||
        widget.workspaceId != oldWidget.workspaceId) {
      unawaited(_fileTreeCubit.setRoots(_workspaceRoots));
    }
    if (widget.cwd != oldWidget.cwd ||
        rootsChanged ||
        widget.preferences.gitVisible != oldWidget.preferences.gitVisible ||
        widget.preferences.fileTreeVisible !=
            oldWidget.preferences.fileTreeVisible) {
      _setupDiskRefresh();
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
  }

  /// Keeps the file tree and git panels warm while their tools are enabled.
  /// Uses the shared [_fsWatcher] when available, else a periodic poll
  /// (SSH/Android). One subscription serves both consumers.
  void _setupDiskRefresh() {
    _diskWatchSub?.cancel();
    _diskWatchSub = null;
    _diskPollTimer?.cancel();
    _diskPollTimer = null;

    final needsFileTree = widget.preferences.fileTreeVisible;
    final needsGit = widget.preferences.gitVisible;
    if (!needsFileTree && !needsGit) return;

    if (needsFileTree) _warmFileTree();
    if (needsGit) _warmGit();

    final watcher = _fsWatcher;
    if (watcher?.isSupported ?? false) {
      _diskWatchSub = watcher!.onChanged.listen(_onDiskChanged);
    } else {
      _diskPollTimer = Timer.periodic(
        _diskPollInterval,
        (_) => _onDiskPoll(),
      );
    }
  }

  void _onDiskChanged(Set<String> changedDirs) {
    if (widget.preferences.fileTreeVisible) {
      _refreshFileTree(changedDirs);
    }
    if (widget.preferences.gitVisible) {
      _warmGit();
    }
  }

  void _onDiskPoll() {
    if (widget.preferences.fileTreeVisible) {
      _warmFileTree();
    }
    if (widget.preferences.gitVisible) {
      _warmGit();
    }
  }

  /// Empty [changedDirs] = unknown scope (e.g. turn-end poke) → full refresh.
  void _refreshFileTree(Set<String> changedDirs) {
    if (changedDirs.isEmpty) {
      unawaited(_fileTreeCubit.refresh());
    } else {
      unawaited(_fileTreeCubit.refreshPaths(changedDirs));
    }
  }

  void _warmFileTree() {
    final state = _fileTreeCubit.state;
    // Cold start: mount roots first; refresh only when root listings are missing.
    if (state.rootPaths.isEmpty) {
      unawaited(_fileTreeCubit.setRoots(_workspaceRoots));
      return;
    }
    final cold = state.rootPaths.any(
      (root) => state.dirCache[root] == null,
    );
    if (cold) {
      unawaited(_fileTreeCubit.refresh());
    }
  }

  void _warmGit() =>
      context.read<GitRepoStore>().refreshAll(_workspaceRoots);

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
    _diskWatchSub?.cancel();
    _diskPollTimer?.cancel();
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
    final activeSessionId = chatCubit.state.activeSessionId;
    final activeSession = activeSessionId == null
        ? null
        : chatCubit.state.sessions
            .where((s) => s.sessionId == activeSessionId)
            .firstOrNull;
    final showAssignFolders = activeSession != null &&
        workspaceTopologyRequiresMemberAssignment(activeSession.folders);
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
            showAssignFolders: showAssignFolders,
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
              final workspaceId = widget.workspaceId;
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
            onAssignFolders: (id) {
              final member = runtimeMembers.firstWhere((m) => m.id == id);
              final activeTab = chatCubit.activeTab;
              final sessionId = activeTab?.info.id ?? '';
              final repo = chatCubit.sessionRepository;
              if (sessionId.isEmpty || repo == null) return;
              unawaited(
                showMemberFolderAssignmentDialog(
                  context,
                  repository: repo,
                  sessionId: sessionId,
                  memberId: member.id,
                  memberLabel:
                      member.name.isEmpty ? context.l10n.memberName : member.name,
                ),
              );
              maybeDismissDrawer();
            },
            onOpenConfigDir: (id) {
              final member = runtimeMembers.firstWhere((m) => m.id == id);
              final activeTab = chatCubit.activeTab;
              final workspaceId = widget.workspaceId;
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
          child: FileTreePanel(
            key: const ValueKey('workspace-file-tree'),
            cubit: _fileTreeCubit,
          ),
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
    // Breadcrumb: current worktree branch, so the file tree / source control
    // make clear which worktree they reflect. Nullable lookup — absent on
    // routes/tests that build the panel without a WorktreeCubit ancestor.
    final wtState = context.watch<WorktreeCubit?>()?.state;
    final branchLabel = (wtState != null && wtState.hasMultipleWorktrees)
        ? _currentWorktreeBranch(wtState)
        : null;
    final panel = TabbedPanel(views: views, scopeId: widget._toolsScopeId);
    return Container(
      key: widget.panelKey,
      child: branchLabel == null
          ? panel
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _WorktreeBreadcrumb(branch: branchLabel),
                Expanded(child: panel),
              ],
            ),
    );
  }

  static String? _currentWorktreeBranch(WorktreeState state) {
    for (final w in state.worktrees) {
      if (workspacePathsEqual(w.path, state.currentWorktreePath)) {
        return w.shortBranch;
      }
    }
    return null;
  }
}

/// Thin header above the right tools showing the current worktree's branch.
class _WorktreeBreadcrumb extends StatelessWidget {
  const _WorktreeBreadcrumb({required this.branch});

  final String branch;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.account_tree_outlined, size: 14, color: cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              branch,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.of(context).bodySmall.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
