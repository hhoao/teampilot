import 'dart:async';
import 'package:shared_ui/shared_ui.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/app_provider_cubit.dart';
import '../../cubits/cli_presets_cubit.dart';
import '../../cubits/chat_cubit.dart';
import '../../cubits/content_search/content_search_cubit.dart';
import '../../cubits/workbench/workbench_cubit.dart';
import '../../cubits/chat/model/session_workbench_view.dart';
import '../../cubits/file_tree_cubit.dart';
import '../../cubits/mailbox_cubit.dart';
import '../../cubits/member_presence_cubit.dart';
import '../../cubits/workspace_tools_cubit.dart';
import '../../utils/session/workspace_tab_session_scope.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_session.dart';
import '../../models/app_provider_config.dart';
import '../../models/member_instance.dart';
import '../../models/runtime_target.dart';
import '../../models/team_config.dart';
import '../../models/workspace.dart';
import '../../models/workspace_launch_context.dart';
import '../../models/workspace_topology.dart';
import '../../pages/home_workspace/workspace/member_detail_dialog.dart';
import '../../pages/home_workspace/workspace/member_config_directory_opener.dart';
import '../../services/cli/member_config/member_config_inspector.dart';
import '../../services/search/content_replacer.dart';
import '../../services/search/content_search_runner.dart';
import '../../services/storage/home_target_controller.dart';
import '../../services/storage/runtime_context.dart';
import '../../services/workspace/workspace_tools_scope.dart';
import '../../utils/debounce/debounce.dart';
import '../../utils/team/team_member_naming.dart';
import '../git/git_source_control_panel.dart';
import 'board_panel.dart';
import 'file_tree_panel.dart';
import 'mailbox_panel.dart';
import 'members_panel.dart';
import 'right_tool_ids.dart';
import 'right_tools_tool_preferences.dart';
import 'search_panel.dart';
import 'tabbed_panel.dart';
import 'tool_view.dart';

/// Index of the search tool within [_buildViews], mirroring its guards.
/// Order: members, fileTree, git, mailbox, board, search.
///
/// [membersVisible] must already fold in the `team != null` condition from
/// [_buildViews]; [showMailbox]/[showBoard] come from a
/// [RightToolsMailboxGate] resolved with the same inputs.
int searchToolIndex({
  required bool isPersonalContext,
  required bool membersVisible,
  required bool fileTreeVisible,
  required bool gitVisible,
  required bool showMailbox,
  required bool showBoard,
}) {
  var i = 0;
  if (!isPersonalContext && membersVisible) i++;
  if (fileTreeVisible) i++;
  if (gitVisible) i++;
  if (showMailbox) i++;
  if (showBoard) i++;
  return i;
}

/// Pokes the shared FS watcher when a session leaves the working set.
class RightToolsWorkingTurnListener extends StatelessWidget {
  const RightToolsWorkingTurnListener({
    required this.onTurnEnd,
    required this.child,
    super.key,
  });

  final VoidCallback onTurnEnd;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return _WorkingSetDelta(onTurnEnd: onTurnEnd, child: child);
  }
}

class _WorkingSetDelta extends StatefulWidget {
  const _WorkingSetDelta({required this.onTurnEnd, required this.child});

  final VoidCallback onTurnEnd;
  final Widget child;

  @override
  State<_WorkingSetDelta> createState() => _WorkingSetDeltaState();
}

class _WorkingSetDeltaState extends State<_WorkingSetDelta> {
  Set<String> _previous = const {};

  @override
  void initState() {
    super.initState();
    _previous = context.read<ChatCubit>().state.busySessionIds;
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<ChatCubit, ChatState>(
      listenWhen: (previous, next) =>
          previous.sessionActivities != next.sessionActivities,
      listener: (context, state) {
        final working = state.busySessionIds;
        if (_previous.difference(working).isNotEmpty) {
          widget.onTurnEnd();
        }
        _previous = working;
      },
      child: widget.child,
    );
  }
}

/// Syncs member presence when the selected team changes.
class RightToolsPresenceTeamSync extends StatefulWidget {
  const RightToolsPresenceTeamSync({
    required this.team,
    required this.child,
    super.key,
  });

  final TeamProfile? team;
  final Widget child;

  @override
  State<RightToolsPresenceTeamSync> createState() =>
      _RightToolsPresenceTeamSyncState();
}

class _RightToolsPresenceTeamSyncState
    extends State<RightToolsPresenceTeamSync> {
  String? _syncedTeamId;
  bool _tickerEnabled = true;

  @override
  Widget build(BuildContext context) {
    final enabled = TickerMode.valuesOf(context).enabled;
    final becameEnabled = enabled && !_tickerEnabled;
    _tickerEnabled = enabled;
    if (!enabled) {
      return widget.child;
    }
    final team = widget.team;
    if (team != null) {
      final teamId = team.id;
      // Re-sync on workspace re-activation (TickerMode re-enable) even when the
      // team id is unchanged: another workspace's panel may have synced a
      // different team into the shared cubit while this workspace was inactive.
      if (becameEnabled || teamId != _syncedTeamId) {
        _syncedTeamId = teamId;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          context.read<MemberPresenceCubit>().syncPresenceTeam(team);
        });
      }
    }
    return widget.child;
  }
}

@immutable
class RightToolsMailboxGate {
  const RightToolsMailboxGate({
    required this.showMailbox,
    required this.showBoard,
    required this.unreadCount,
  });

  final bool showMailbox;
  final bool showBoard;
  final int unreadCount;

  static RightToolsMailboxGate resolve({
    required bool isPersonalContext,
    required TeamProfile? team,
    required bool hasTeamBus,
    required bool boardVisible,
    required int unreadCount,
  }) {
    final showMailbox =
        !isPersonalContext &&
        team != null &&
        team.teamMode == TeamMode.mixed &&
        hasTeamBus;
    return RightToolsMailboxGate(
      showMailbox: showMailbox,
      showBoard: showMailbox && boardVisible,
      unreadCount: unreadCount,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is RightToolsMailboxGate &&
        showMailbox == other.showMailbox &&
        showBoard == other.showBoard &&
        unreadCount == other.unreadCount;
  }

  @override
  int get hashCode => Object.hash(showMailbox, showBoard, unreadCount);
}

@immutable
class RightToolsChatSlice {
  const RightToolsChatSlice({
    required this.selectedMemberId,
    required this.hasActiveTab,
    required this.activeSessionId,
    required this.hasTeamBus,
    required this.memberSelectionVersion,
    this.persistedSession,
  });

  factory RightToolsChatSlice.fromScope({
    required String selectedMemberId,
    required String? activeSessionId,
    required bool hasActiveTab,
    required bool hasTeamBus,
    required int memberSelectionVersion,
    AppSession? persistedSession,
  }) {
    return RightToolsChatSlice(
      selectedMemberId: selectedMemberId,
      hasActiveTab: hasActiveTab,
      activeSessionId: activeSessionId,
      hasTeamBus: hasTeamBus,
      memberSelectionVersion: memberSelectionVersion,
      persistedSession: persistedSession,
    );
  }

  final String selectedMemberId;
  final bool hasActiveTab;
  final String? activeSessionId;
  final bool hasTeamBus;
  final int memberSelectionVersion;
  final AppSession? persistedSession;

  @override
  bool operator ==(Object other) {
    return other is RightToolsChatSlice &&
        selectedMemberId == other.selectedMemberId &&
        hasActiveTab == other.hasActiveTab &&
        activeSessionId == other.activeSessionId &&
        hasTeamBus == other.hasTeamBus &&
        memberSelectionVersion == other.memberSelectionVersion &&
        identical(persistedSession, other.persistedSession);
  }

  @override
  int get hashCode => Object.hash(
    selectedMemberId,
    hasActiveTab,
    activeSessionId,
    hasTeamBus,
    memberSelectionVersion,
    persistedSession,
  );
}

/// Builds the tabbed tool views with narrow bloc subscriptions.
class RightToolsToolViews extends StatefulWidget {
  const RightToolsToolViews({
    required this.preferences,
    required this.cwd,
    required this.workspaceId,
    required this.toolsScopeId,
    required this.isPersonalContext,
    required this.team,
    required this.dismissDrawerOnAction,
    required this.fileTreeCubit,
    required this.workContext,
    required this.scope,
    required this.searchFocusRequest,
    super.key,
  });

  final RightToolsToolPreferences preferences;
  final String cwd;
  final String workspaceId;
  final String toolsScopeId;
  final bool isPersonalContext;
  final TeamProfile? team;
  final bool dismissDrawerOnAction;
  final FileTreeCubit fileTreeCubit;
  final RuntimeContext workContext;
  final WorkspaceToolsScopeState scope;

  /// Bumped by the Ctrl+Shift+F command host to focus the query field.
  final ValueNotifier<int> searchFocusRequest;

  @override
  State<RightToolsToolViews> createState() => _RightToolsToolViewsState();
}

@immutable
class _RightToolsViewsCacheKey {
  const _RightToolsViewsCacheKey({
    required this.preferences,
    required this.isPersonalContext,
    required this.team,
    required this.chatSlice,
    required this.mailboxGate,
    required this.scopeRoots,
    required this.scopeTargetId,
    required this.cwd,
    required this.workspaceId,
    required this.toolsScopeId,
  });

  final RightToolsToolPreferences preferences;
  final bool isPersonalContext;
  final TeamProfile? team;
  final RightToolsChatSlice chatSlice;
  final RightToolsMailboxGate mailboxGate;
  final List<String> scopeRoots;
  final String? scopeTargetId;
  final String cwd;
  final String workspaceId;
  final String toolsScopeId;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is _RightToolsViewsCacheKey &&
            preferences == other.preferences &&
            isPersonalContext == other.isPersonalContext &&
            team == other.team &&
            chatSlice == other.chatSlice &&
            mailboxGate == other.mailboxGate &&
            listEquals(scopeRoots, other.scopeRoots) &&
            scopeTargetId == other.scopeTargetId &&
            cwd == other.cwd &&
            workspaceId == other.workspaceId &&
            toolsScopeId == other.toolsScopeId;
  }

  @override
  int get hashCode => Object.hash(
    preferences,
    isPersonalContext,
    team,
    chatSlice,
    mailboxGate,
    Object.hashAll(scopeRoots),
    scopeTargetId,
    cwd,
    workspaceId,
    toolsScopeId,
  );
}

class _RightToolsToolViewsState extends State<RightToolsToolViews> {
  _RightToolsViewsCacheKey? _cacheKey;
  List<ToolView>? _cachedViews;
  var _mixedDefaultsSeeded = false;

  @override
  void didUpdateWidget(covariant RightToolsToolViews oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.toolsScopeId != widget.toolsScopeId) {
      _mixedDefaultsSeeded = false;
    }
  }

  void _seedMixedTeamDefaultsIfNeeded(
    BuildContext context,
    List<ToolView> views,
  ) {
    if (_mixedDefaultsSeeded) return;
    final team = widget.team;
    if (widget.isPersonalContext || team?.teamMode != TeamMode.mixed) return;

    final available = views.map((v) => v.id).toSet();
    final defaults = [
      for (final id in RightToolIds.mixedTeamDefaults)
        if (available.contains(id)) id,
    ];
    if (defaults.isEmpty) return;

    _mixedDefaultsSeeded = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<WorkspaceToolsCubit>().openDefaultsIfEmpty(
        widget.toolsScopeId,
        defaults,
        selectId: RightToolIds.members,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final mailboxCubit = _maybeMailboxCubit(context);
    if (mailboxCubit == null) {
      return _buildWithUnread(context, unreadCount: 0, hasMailboxCubit: false);
    }
    return BlocSelector<MailboxCubit, MailboxState, int>(
      bloc: mailboxCubit,
      selector: (state) => state.totalUnread,
      builder: (context, unreadCount) => _buildWithUnread(
        context,
        unreadCount: unreadCount,
        hasMailboxCubit: true,
      ),
    );
  }

  Widget _buildWithUnread(
    BuildContext context, {
    required int unreadCount,
    required bool hasMailboxCubit,
  }) {
    final team = widget.team;
    if (!widget.isPersonalContext && team == null) {
      return const SizedBox.shrink();
    }

    final workbench = context.read<WorkbenchCubit>();
    final activeSessionId = context.select<WorkbenchCubit, String?>(
      (w) => scopedActiveSessionId(w, widget.toolsScopeId),
    );
    final chatSlice = context.select<ChatCubit, RightToolsChatSlice>(
      (c) => RightToolsChatSlice.fromScope(
        selectedMemberId: scopedSelectedMemberId(
          workbench,
          c,
          widget.toolsScopeId,
        ),
        activeSessionId: activeSessionId,
        hasActiveTab: c.tabStore
            .tabsForWorkspace(widget.toolsScopeId)
            .isNotEmpty,
        hasTeamBus: scopedTeamBus(workbench, c, widget.toolsScopeId) != null,
        memberSelectionVersion: c.state.memberSelectionVersion,
        persistedSession: scopedActiveChatTab(
          workbench,
          c,
          widget.toolsScopeId,
        )?.persistedSession,
      ),
    );

    final mailboxGate = RightToolsMailboxGate.resolve(
      isPersonalContext: widget.isPersonalContext,
      team: team,
      hasTeamBus: chatSlice.hasTeamBus && hasMailboxCubit,
      boardVisible: widget.preferences.boardVisible,
      unreadCount: unreadCount,
    );

    final cacheKey = _RightToolsViewsCacheKey(
      preferences: widget.preferences,
      isPersonalContext: widget.isPersonalContext,
      team: team,
      chatSlice: chatSlice,
      mailboxGate: mailboxGate,
      scopeRoots: widget.scope.roots,
      scopeTargetId: widget.scope.tools?.targetId,
      cwd: widget.cwd,
      workspaceId: widget.workspaceId,
      toolsScopeId: widget.toolsScopeId,
    );

    if (_cacheKey != cacheKey || _cachedViews == null) {
      _cacheKey = cacheKey;
      _cachedViews = _buildViews(
        context,
        team: team,
        chatSlice: chatSlice,
        mailboxGate: mailboxGate,
      );
    }

    _seedMixedTeamDefaultsIfNeeded(context, _cachedViews!);

    return TabbedPanel(views: _cachedViews!, scopeId: widget.toolsScopeId);
  }

  static MailboxCubit? _maybeMailboxCubit(BuildContext context) {
    try {
      return context.read<MailboxCubit>();
    } on Object {
      return null;
    }
  }

  List<ToolView> _buildViews(
    BuildContext context, {
    required TeamProfile? team,
    required RightToolsChatSlice chatSlice,
    required RightToolsMailboxGate mailboxGate,
  }) {
    final l10n = context.l10n;
    final views = <ToolView>[];
    void maybeDismissDrawer() {
      if (widget.dismissDrawerOnAction) {
        Navigator.of(context).maybePop();
      }
    }

    if (!widget.isPersonalContext &&
        widget.preferences.membersVisible &&
        team != null) {
      final session = chatSlice.persistedSession;
      final runtimeMembers = session != null && session.members.isNotEmpty
          ? sessionRosterMembers(session, team)
          : runtimeRosterMembers(team);
      final members = [...runtimeMembers]
        ..sort((a, b) {
          if (TeamMemberNaming.isTeamLead(a)) return -1;
          if (TeamMemberNaming.isTeamLead(b)) return 1;
          return a.name.compareTo(b.name);
        });
      // Spec: session targets when present; else remembered workspace pins.
      // Empty session map falls back to remembered (hydrate edge case).
      final MemberTargetAssignments memberTargets;
      if (session != null && session.memberTargets.isNotEmpty) {
        memberTargets = session.memberTargets;
      } else {
        final workspace = context
            .read<ChatCubit>()
            .state
            .workspaces
            .where((w) => w.workspaceId == widget.workspaceId)
            .firstOrNull;
        memberTargets = rememberedMemberTargets(
          workspace?.memberTargetsByTeam ?? const {},
          team.id,
        );
      }
      views.add(
        ToolView(
          id: RightToolIds.members,
          icon: Icons.groups_outlined,
          label: l10n.members,
          child: _ScopedMembersPanel(
            team: team,
            members: members,
            runtimeMembers: runtimeMembers,
            memberTargets: memberTargets,
            selectedMemberId: chatSlice.selectedMemberId,
            canViewDetail: chatSlice.hasActiveTab,
            workspaceId: widget.workspaceId,
            tabScopeId: widget.toolsScopeId,
            cwd: widget.cwd,
            scope: widget.scope,
            maybeDismissDrawer: maybeDismissDrawer,
          ),
        ),
      );
    }

    if (widget.preferences.fileTreeVisible) {
      views.add(
        ToolView(
          id: RightToolIds.fileTree,
          icon: Icons.folder_outlined,
          label: l10n.fileTree,
          child: FileTreePanel(
            key: const ValueKey('workspace-file-tree'),
            cubit: widget.fileTreeCubit,
            workContext: widget.workContext,
            workspaceId: widget.workspaceId,
          ),
        ),
      );
    }

    if (widget.preferences.gitVisible) {
      views.add(
        ToolView(
          id: RightToolIds.git,
          icon: Icons.account_tree_outlined,
          label: l10n.sourceControl,
          child: GitSourceControlPanel(
            roots: widget.scope.roots,
            workContext: widget.workContext,
            workspaceId: widget.workspaceId,
          ),
        ),
      );
    }

    if (mailboxGate.showMailbox && team != null) {
      views.add(
        ToolView(
          id: RightToolIds.mailbox,
          icon: Icons.mail_outline,
          label: l10n.mailbox,
          badgeCount: mailboxGate.unreadCount,
          child: MailboxPanel(team: team, cwd: widget.cwd),
        ),
      );
    }

    if (mailboxGate.showBoard && team != null) {
      views.add(
        ToolView(
          id: RightToolIds.board,
          icon: Icons.view_kanban_outlined,
          label: l10n.board,
          child: BoardPanel(team: team, cwd: widget.cwd),
        ),
      );
    }

    // Search stays LAST: Task 4 shortcuts resolve the tool index by position.
    if (widget.preferences.searchVisible) {
      final root = widget.scope.roots.firstOrNull ?? widget.cwd;
      final fs = widget.workContext.filesystem;
      views.add(
        ToolView(
          id: RightToolIds.search,
          icon: Icons.search_outlined,
          label: l10n.workspaceSearchPanel,
          child: BlocProvider(
            lazy: false,
            create: (context) => ContentSearchCubit(
              runnerFactory: (_) => ContentSearchRunner(fs: fs, root: root),
              replacerFactory: () => ContentReplacer(fs: fs),
            ),
            child: WorkspaceSearchPanel(
              workspaceId: widget.workspaceId,
              root: root,
              fs: fs,
              focusRequest: widget.searchFocusRequest,
            ),
          ),
        ),
      );
    }

    return views;
  }
}

class _ScopedMembersPanel extends StatefulWidget {
  const _ScopedMembersPanel({
    required this.team,
    required this.members,
    required this.runtimeMembers,
    required this.memberTargets,
    required this.selectedMemberId,
    required this.canViewDetail,
    required this.workspaceId,
    required this.tabScopeId,
    required this.cwd,
    required this.scope,
    required this.maybeDismissDrawer,
  });

  final TeamProfile team;
  final List<TeamMemberConfig> members;
  final List<TeamMemberConfig> runtimeMembers;
  final MemberTargetAssignments memberTargets;
  final String selectedMemberId;
  final bool canViewDetail;
  final String workspaceId;
  final String tabScopeId;
  final String cwd;
  final WorkspaceToolsScopeState scope;
  final VoidCallback maybeDismissDrawer;

  @override
  State<_ScopedMembersPanel> createState() => _ScopedMembersPanelState();
}

class _ScopedMembersPanelState extends State<_ScopedMembersPanel> {
  List<RuntimeTarget> _runtimeTargets = const [];
  Future<void>? _targetsLoad;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _targetsLoad ??= _loadSelectableTargets();
  }

  Future<void> _loadSelectableTargets() async {
    try {
      final targets = await context
          .read<HomeTargetController>()
          .listSelectable();
      if (!mounted) return;
      setState(() => _runtimeTargets = targets);
    } on Object {
      // HomeTargetController unavailable in widget tests.
    }
  }

  @override
  Widget build(BuildContext context) {
    final providersByCli = context
        .select<AppProviderCubit, Map<CliTool, List<AppProviderConfig>>>(
          (c) => c.state.providersByCli,
        );
    return MembersPanel(
      team: widget.team,
      members: widget.members,
      memberPresence: const {},
      providersByCli: providersByCli,
      selectedMemberId: widget.selectedMemberId,
      memberTargets: widget.memberTargets,
      runtimeTargets: _runtimeTargets,
      groupByMachine: widget.team.teamMode == TeamMode.mixed,
      onSelected: (id) => _onMemberRowTap(context, id),
      onSwitchTo: (id) => _switchToMember(context, id),
      onOpen: (id) => _openMember(context, id),
      onLaunchAll: throttledAsync('right_tools_launch_all', () async {
        await context.read<ChatCubit>().launchAllMembers(
          widget.team,
          workspaceCwd: widget.cwd,
        );
        widget.maybeDismissDrawer();
      }),
      canViewDetail: widget.canViewDetail,
      onViewDetail: (id) => _viewDetail(context, id),
      onOpenConfigDir: (id) => _openConfigDir(context, id),
    );
  }

  SessionWorkbenchView _activeWorkbenchView(ChatCubit chat) {
    final sessionId = chat.activeTab?.info.id;
    if (sessionId == null || sessionId.isEmpty) {
      return SessionWorkbenchView.chat;
    }
    // The pod is the canonical view source; fall back to the tab during the
    // thin-ChatCubit transition.
    final podView = chat.podFor(sessionId)?.view;
    if (podView != null) return podView;
    final tab = chat.tabStore.openTabBySessionId(sessionId);
    return tab?.workbenchView ?? SessionWorkbenchView.chat;
  }

  void _onMemberRowTap(BuildContext context, String id) {
    final chat = context.read<ChatCubit>();
    if (_activeWorkbenchView(chat) == SessionWorkbenchView.chat) {
      _switchToMember(context, id);
      return;
    }
    _openMember(context, id);
  }

  void _switchToMember(BuildContext context, String id) {
    context.read<ChatCubit>().selectMember(id, tabScopeId: widget.tabScopeId);
    widget.maybeDismissDrawer();
  }

  void _openMember(BuildContext context, String id) {
    final chat = context.read<ChatCubit>();
    final sessionId = chat.activeTab?.info.id;
    if (sessionId != null && sessionId.isNotEmpty) {
      chat.setSessionWorkbenchView(sessionId, SessionWorkbenchView.terminal);
    }
    final member = widget.runtimeMembers.firstWhere((m) => m.id == id);
    unawaited(
      chat.openMemberTab(widget.team, member, workspaceCwd: widget.cwd),
    );
    widget.maybeDismissDrawer();
  }

  Future<void> _viewDetail(BuildContext context, String id) async {
    final member = widget.runtimeMembers.firstWhere((m) => m.id == id);
    final chatCubit = context.read<ChatCubit>();
    final activeTab = chatCubit.activeTab;
    final activeSession = activeTab == null
        ? null
        : chatCubit.state.sessions
              .where((s) => s.sessionId == activeTab.info.id)
              .firstOrNull;
    await showMemberDetailDialog(
      context,
      workspaceId: widget.workspaceId,
      sessionId: activeTab?.info.id ?? '',
      team: widget.team,
      member: member,
      lifecycle: chatCubit.lifecycle,
      session: activeSession,
    );
    widget.maybeDismissDrawer();
  }

  Future<void> _openConfigDir(BuildContext context, String id) async {
    final member = widget.runtimeMembers.firstWhere((m) => m.id == id);
    final chatCubit = context.read<ChatCubit>();
    final activeTab = chatCubit.activeTab;
    final session = activeTab == null
        ? null
        : chatCubit.state.sessions
              .where((s) => s.sessionId == activeTab.info.id)
              .firstOrNull;
    if (session == null) return;

    final cached = activeTab?.memberConfigDirs[id]?.trim();
    final launchCtx = WorkspaceLaunchContext(
      session: session,
      workspace: Workspace(
        workspaceId: widget.workspaceId,
        folders: widget.scope.effectiveFolders,
        createdAt: 0,
      ),
    );
    final workContext = await chatCubit.lifecycle.launchWorkContext(
      launchCtx,
      memberId: member.id,
    );
    final path = cached?.isNotEmpty == true
        ? cached!
        : (await MemberConfigInspector().inspect(
            workspaceId: widget.workspaceId,
            sessionId: activeTab?.info.id ?? '',
            team: widget.team,
            member: member,
            workContext: workContext,
            globalPresets: context.read<CliPresetsCubit>().state.presets,
            preferExpectedRuntimeDir: true,
          )).resolvedDir;
    if (!context.mounted || path.isEmpty) return;
    await openMemberConfigDirectory(
      context,
      path: path,
      workContext: workContext,
    );
    widget.maybeDismissDrawer();
  }
}
