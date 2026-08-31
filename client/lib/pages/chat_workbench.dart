import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:shared_ui/shared_ui.dart';
import '../widgets/app_toast/app_toast.dart';

import '../cubits/chat/model/session_connect_request.dart';
import '../cubits/chat/model/chat_tab.dart';
import '../cubits/chat_cubit.dart';
import '../cubits/layout_cubit.dart';
import '../cubits/launch_profile_cubit.dart';
import '../cubits/session_preferences_cubit.dart';
import '../cubits/workbench/workbench_cubit.dart';
import '../l10n/l10n_extensions.dart';
import '../models/app_session.dart';
import '../models/workspace.dart';
import '../models/workspace_launch_context.dart';
import '../models/team_config.dart';
import '../repositories/session_repository.dart';
import '../repositories/ssh_profile_repository.dart';
import '../services/storage/home_target_controller.dart';
import '../services/io/filesystem.dart';
import '../services/terminal/terminal_session.dart';
import '../services/terminal/terminal_theme_mapper.dart';
import '../services/workbench/session_member_filesystem.dart';
import '../services/workbench/workbench_editor_opener.dart';
import '../services/workspace/dead_ssh_target_error.dart';
import '../services/workspace/target_liveness.dart';
import '../services/workspace/workspace_tools_scope.dart';
import '../theme/workspace_surface_layers.dart';
import '../utils/ui/app_keys.dart';
import '../widgets/workspace/workspace_dead_target_remap_dialog.dart';
import 'home_workspace/workspace/workspace_route_active_scope.dart';
import 'chat/chat_workbench_overlay.dart';
import 'chat/chat_workbench_placeholders.dart';
import 'chat/chat_workbench_remote_provision_view.dart';
import 'chat/chat_workbench_slice.dart';
import 'chat/chat_workbench_terminal.dart';
import '../models/member_remote_provision_progress.dart';
import 'chat/history_continue_delivery.dart';
import 'chat/session_chat_continue_seat.dart';
import 'chat/session_chat_view.dart';
import 'chat/session_history_review_submit.dart';
import 'chat/session_launch_error_banner.dart';
import 'chat/session_launch_error_visibility.dart';
import 'chat/session_launch_failure_presenter.dart';
import 'chat/session_workbench_view_toggle.dart';

class ChatWorkbench extends StatefulWidget {
  const ChatWorkbench({
    required this.workspaceId,
    required this.workbenchSlice,
    this.tabScopeId,
    this.profileId,
    this.routeActive = true,
    this.sessionId,
    this.isPersonalContext = false,
    this.team,
    super.key,
  });

  final String workspaceId;
  final String? tabScopeId;
  final String? profileId;
  final bool routeActive;
  final String? sessionId;
  final bool isPersonalContext;
  final TeamProfile? team;
  final ChatWorkbenchSlice workbenchSlice;

  @override
  State<ChatWorkbench> createState() => _ChatWorkbenchState();
}

class _ChatWorkbenchState extends State<ChatWorkbench> {
  TerminalController _terminalController = TerminalController();

  var _findVisible = false;
  var _remappingDeadTarget = false;
  int? _lastTerminalThemeFingerprint;
  TerminalSession? _themeSyncedSession;
  String? _lastThemeSyncedMemberId;

  @override
  void dispose() {
    _terminalController.dispose();
    super.dispose();
  }

  Future<void> _openTerminalLink(String link) async {
    if (!mounted) return;
    final chatCubit = context.read<ChatCubit>();
    final sessionId = chatCubit.activeTab?.info.id.trim() ?? '';
    AppSession? appSession;
    if (sessionId.isNotEmpty) {
      for (final s in chatCubit.state.sessions) {
        if (s.sessionId == sessionId && s.workspaceId == widget.workspaceId) {
          appSession = s;
          break;
        }
      }
    }
    Workspace? workspace;
    for (final w in chatCubit.state.workspaces) {
      if (w.workspaceId == widget.workspaceId) {
        workspace = w;
        break;
      }
    }

    final memberId = chatCubit.activeTab?.selectedMemberId ?? '';
    final isPersonal = appSession?.sessionTeam.trim().isEmpty ?? true;
    final historyMemberId = isPersonal ? '' : memberId;

    Filesystem? fs;
    if (appSession != null && workspace != null) {
      fs = await resolveSessionMemberFilesystem(
        lifecycle: chatCubit.lifecycle,
        launchContext: WorkspaceLaunchContext(
          session: appSession,
          workspace: workspace,
        ),
        memberId: historyMemberId,
        toolsScope: WorkspaceToolsScope.maybeOf(context),
      );
    } else {
      fs = WorkspaceToolsScope.maybeOf(context)?.tools?.context.filesystem;
    }
    if (!mounted) return;

    await openChatWorkbenchTerminalLink(
      link: link,
      chatCubit: chatCubit,
      editorOpener: context.read<WorkbenchEditorOpener>(),
      workspaceId: widget.workspaceId,
      isMounted: () => mounted,
      fs: fs,
    );
  }

  SessionConnectRequest _connectRequest({
    required bool isPersonal,
    TeamProfile? team,
  }) {
    if (isPersonal) {
      return PersonalSessionConnect(workspaceId: widget.workspaceId);
    }
    return TeamSessionConnect(team!);
  }

  Future<void> _restartWorkspace({
    required bool isPersonal,
    TeamProfile? team,
  }) async {
    await context.read<ChatCubit>().restartWorkspaceSession(
      _connectRequest(isPersonal: isPersonal, team: team),
      repo: context.read<SessionRepository>(),
    );
  }

  TargetLiveness _targetLiveness(BuildContext context) =>
      DefaultTargetLiveness(sshProfiles: context.read<SshProfileRepository>());

  Future<void> _remapDeadTargetFromLaunch({
    required String launchError,
    required String sessionId,
  }) async {
    final fromTargetId = deadSshTargetIdFromError(launchError);
    if (fromTargetId == null || _remappingDeadTarget) return;

    final chat = context.read<ChatCubit>();
    final workspace = chat.state.workspaces.firstWhereOrNull(
      (w) => w.workspaceId == widget.workspaceId,
    );
    if (workspace == null) return;

    setState(() => _remappingDeadTarget = true);
    final liveness = _targetLiveness(context);
    final homeTarget = context.read<HomeTargetController>();
    final repo = context.read<SessionRepository>();
    try {
      final selectable = await homeTarget.listSelectable();
      if (!mounted) return;
      final to = await showWorkspaceDeadTargetRemapDialog(
        context: context,
        fromTargetId: fromTargetId,
        deadTargetIds: [fromTargetId],
        selectable: selectable,
        liveness: liveness,
      );
      if (to == null || !mounted) return;

      final updated = await repo.remapWorkspaceTarget(
        workspace.workspaceId,
        fromTargetId: fromTargetId,
        toTargetId: to,
        liveness: liveness,
      );
      chat.invalidateWorkspaceProvision(updated.workspace);
      chat.patchWorkspaceAndSessions(updated.workspace, updated.sessions);
      chat.clearLaunchError(sessionId);
    } on Object {
      if (mounted) {
        AppToast.show(
          context,
          message: context.l10n.workspaceDeadTargetRemapFailed,
          variant: TpToastVariant.error,
        );
      }
    } finally {
      if (mounted) setState(() => _remappingDeadTarget = false);
    }
  }

  void _syncTerminalTheme(
    TerminalSession session,
    TerminalTheme theme,
    String selectedMemberId,
  ) {
    final fp = terminalThemeFingerprint(theme);
    if (_themeSyncedSession == session &&
        _lastTerminalThemeFingerprint == fp &&
        _lastThemeSyncedMemberId == selectedMemberId) {
      return;
    }
    session.applyTerminalTheme(theme);
    _themeSyncedSession = session;
    _lastTerminalThemeFingerprint = fp;
    _lastThemeSyncedMemberId = selectedMemberId;
  }

  Widget _buildRunningTerminal({
    required TerminalSession session,
    required TerminalTheme terminalTheme,
    required ChatCubit chatCubit,
    required bool isPersonal,
    required TeamProfile? team,
    AppSession? appSession,
    String historyMemberId = '',
    required bool autofocus,
  }) {
    _terminalController = bindChatWorkbenchTerminalController(
      _terminalController,
      session.engine,
    );
    return ChatWorkbenchRunningTerminal(
      session: session,
      terminalTheme: terminalTheme,
      terminalController: _terminalController,
      findVisible: _findVisible,
      autofocus: autofocus,
      appSession: appSession,
      historyMemberId: historyMemberId,
      team: team,
      onFindVisibleChanged: (visible) => setState(() => _findVisible = visible),
      onControllerSearchChanged: () => setState(() {}),
      onOpenLink: _openTerminalLink,
      onDisconnect: () => chatCubit.disconnectSession(),
      onRestart: () => _restartWorkspace(isPersonal: isPersonal, team: team),
    );
  }

  @override
  Widget build(BuildContext context) {
    final slice = widget.workbenchSlice;
    final team = widget.team;
    return _ChatWorkbenchBody(
      workspaceId: widget.workspaceId,
      tabScopeId: widget.tabScopeId ?? widget.workspaceId,
      profileId: widget.profileId,
      routeActive: widget.routeActive,
      sessionId: widget.sessionId,
      isPersonalContext: widget.isPersonalContext,
      slice: slice,
      team: team,
      findVisible: _findVisible,
      onSyncTerminalTheme: _syncTerminalTheme,
      buildRunningTerminal: _buildRunningTerminal,
      onRemapDeadTargetFromLaunch: _remapDeadTargetFromLaunch,
    );
  }
}

class _ChatWorkbenchBody extends StatelessWidget {
  const _ChatWorkbenchBody({
    required this.workspaceId,
    required this.tabScopeId,
    this.profileId,
    required this.routeActive,
    required this.sessionId,
    required this.isPersonalContext,
    required this.slice,
    required this.team,
    required this.findVisible,
    required this.onSyncTerminalTheme,
    required this.buildRunningTerminal,
    required this.onRemapDeadTargetFromLaunch,
  });

  final String workspaceId;
  final String tabScopeId;
  final String? profileId;
  final bool routeActive;
  final String? sessionId;
  final bool isPersonalContext;
  final ChatWorkbenchSlice slice;
  final TeamProfile? team;
  final bool findVisible;
  final void Function(TerminalSession, TerminalTheme, String)
  onSyncTerminalTheme;
  final Widget Function({
    required TerminalSession session,
    required TerminalTheme terminalTheme,
    required ChatCubit chatCubit,
    required bool isPersonal,
    required TeamProfile? team,
    AppSession? appSession,
    String historyMemberId,
    required bool autofocus,
  })
  buildRunningTerminal;
  final Future<void> Function({
    required String launchError,
    required String sessionId,
  })
  onRemapDeadTargetFromLaunch;

  @override
  Widget build(BuildContext context) {
    final slice = this.slice;
    final team = this.team;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final terminalThemeMode = context.select<LayoutCubit, String>(
      (cubit) => cubit.state.preferences.terminalThemeMode,
    );
    final terminalTheme = teampilotTerminalTheme(
      cs,
      isDark: isDark,
      mode: terminalThemeMode,
      chrome: WorkspacePageChrome.workspace,
    );
    final terminalBackground = Color(0xFF000000 | terminalTheme.background);
    final chatCubit = context.read<ChatCubit>();
    final activeId = slice.activeSessionId;
    if (activeId == null) {
      return const Center(child: CircularProgressIndicator());
    }

    // Pod state (phase / view) is read from the pod ChangeNotifier, not from
    // ChatCubit — pod changes no longer trigger global ChatState emits.
    final pod = activeId.isNotEmpty ? chatCubit.podRuntime(activeId) : null;

    final launchError =
        routeActive && chatCubit.tabStore.activeWorkspaceId == tabScopeId
        ? (chatCubit.activeLaunchError ?? slice.sessionLaunchError)
        : slice.sessionLaunchError;

    // Pod-state values cached here; the ListenableBuilder below re-reads them
    // on every pod notification so sessionConnectInProgress / workbenchView
    // stay current without a global ChatCubit emit.
    bool readConnectInProgress() => pod?.state.phase.isLaunching ?? false;

    SessionWorkbenchView readWorkbenchView() {
      if (activeId.isEmpty) {
        return SessionWorkbenchView.chat;
      }
      final podView = pod?.state.view;
      if (podView != null) return podView;
      final tab = chatCubit.tabStore.openTabBySessionId(activeId);
      return tab?.workbenchView ?? SessionWorkbenchView.chat;
    }

    Widget buildPodDependentBody(BuildContext context) {
      final connectInProgress = readConnectInProgress();
      final view = readWorkbenchView();
      // Chat docks bare icons into the task-board capsule; terminal and other
      // overlays float the standalone pill chrome.
      final dockedViewToggle = SessionWorkbenchViewIcons(
        workspaceId: workspaceId,
        sessionId: activeId,
      );
      final floatingViewToggle = SessionWorkbenchViewToggle(
        workspaceId: workspaceId,
        sessionId: activeId,
      );

      Widget body;
      final session = _resolveSession(
        chatCubit: chatCubit,
        slice: slice,
        team: team,
      );
      if (session == null) {
        if (view == SessionWorkbenchView.chat) {
          body = _buildSessionChatView(
            context,
            chatCubit: chatCubit,
            team: team,
            launchError: launchError,
            sessionConnectInProgress: connectInProgress,
            viewToggle: dockedViewToggle,
          );
        } else {
          var placeholder = false;
          final sid = slice.activeSessionId;
          if (sid != null && sid.isNotEmpty) {
            final tab = chatCubit.tabStore.openTabBySessionId(sid);
            final appSession = tab?.persistedSession;
            placeholder =
                appSession != null && appSession.sessionTeam.trim().isEmpty;
          }
          body = placeholder
              ? _buildTerminalPlaceholder(context, chatCubit: chatCubit)
              : const Center(child: CircularProgressIndicator());
        }
      } else {
        onSyncTerminalTheme(session, terminalTheme, slice.selectedMemberId);

        final memberId = slice.selectedMemberId.isNotEmpty
            ? slice.selectedMemberId
            : '';
        final remoteProvision = context
            .select<ChatCubit, MemberRemoteProvisionProgress?>((c) {
              final sid = slice.activeSessionId;
              if (sid == null || sid.isEmpty) return null;
              final mid = memberId.isNotEmpty
                  ? memberId
                  : c.tabStore.openTabBySessionId(sid)?.selectedMemberId ?? '';
              if (mid.isEmpty) return null;
              return c.tabStore
                  .openTabBySessionId(sid)
                  ?.memberRemoteProvision[mid];
            });

        body = Container(
          key: AppKeys.chatWorkspace,
          color: cs.surface,
          child: ColoredBox(
            color: terminalBackground,
            child: _buildTerminalBody(
              context,
              session: session,
              terminalTheme: terminalTheme,
              chatCubit: chatCubit,
              team: team,
              sessionConnectInProgress: connectInProgress,
              launchError: launchError,
              workbenchView: view,
              remoteProvision: remoteProvision,
              dockedViewToggle: dockedViewToggle,
              floatingViewToggle: floatingViewToggle,
            ),
          ),
        );
      }

      return Stack(
        fit: StackFit.expand,
        children: [
          body,
          // Floating Chat/Terminal capsule for non-chat surfaces only; in the
          // chat view the bare icons dock into the top-right task-board
          // capsule instead (one capsule, no overlap).
          if (view != SessionWorkbenchView.chat)
            Positioned(
              top: context.tpSpacing.sm,
              right: context.tpSpacing.sm,
              child: floatingViewToggle,
            ),
        ],
      );
    }

    if (pod != null) {
      return ListenableBuilder(
        listenable: pod,
        builder: (context, _) => buildPodDependentBody(context),
      );
    }
    return buildPodDependentBody(context);
  }

  TerminalSession? _resolveSession({
    required ChatCubit chatCubit,
    required ChatWorkbenchSlice slice,
    required TeamProfile? team,
  }) {
    final activeId = slice.activeSessionId;
    if (activeId == null || activeId.isEmpty) return null;

    ChatTab? matchedTab;
    for (final tab in chatCubit.tabStore.tabsForWorkspace(tabScopeId)) {
      if (tab.info.id == activeId) {
        matchedTab = tab;
        break;
      }
    }
    if (matchedTab == null) return null;

    final memberId = slice.selectedMemberId.isNotEmpty
        ? slice.selectedMemberId
        : matchedTab.selectedMemberId;
    final shell = matchedTab.memberShells[memberId] ?? matchedTab.resumeSession;
    if (shell != null) return shell;

    // Pre-connect placeholder shell for the foreground team tab only.
    if (routeActive &&
        chatCubit.tabStore.activeWorkspaceId == tabScopeId &&
        !isPersonalContext &&
        team != null) {
      return chatCubit.ensureSession(team);
    }
    return null;
  }

  AppSession? _resolveAppSession({
    required ChatCubit chatCubit,
    required ChatWorkbenchSlice slice,
  }) {
    final activeId = slice.activeSessionId;
    if (activeId == null || activeId.isEmpty) return null;

    for (final session in chatCubit.state.sessions) {
      if (session.sessionId == activeId) return session;
    }

    for (final tab in chatCubit.tabStore.tabsForWorkspace(tabScopeId)) {
      if (tab.info.id == activeId) {
        return tab.persistedSession;
      }
    }
    return null;
  }

  Widget _buildTerminalBody(
    BuildContext context, {
    required TerminalSession session,
    required TerminalTheme terminalTheme,
    required ChatCubit chatCubit,
    required TeamProfile? team,
    required bool sessionConnectInProgress,
    required String? launchError,
    required SessionWorkbenchView workbenchView,
    required MemberRemoteProvisionProgress? remoteProvision,
    required Widget dockedViewToggle,
    required Widget floatingViewToggle,
  }) {
    final routeForeground =
        routeActive && WorkspaceRouteActiveScope.routeActiveOf(context);
    final tickerActive = TickerMode.valuesOf(context).enabled;
    final terminalVisible = routeForeground && tickerActive;

    final showRemoteProvision = remoteProvision != null && !session.isRunning;
    // Keep the Alacritty surface mounted after a non-zero CLI exit so scrollback
    // (and the "[process exited …]" line) stays inspectable under the error
    // banner. Previously isRunning=false unmounted the terminal → empty pane.
    final hasLaunchError = (launchError ?? '').trim().isNotEmpty;
    final mountTerminalForLayout = shouldMountWorkbenchTerminal(
      sessionConnectInProgress: sessionConnectInProgress,
      sessionRunning: session.isRunning,
      showRemoteProvision: showRemoteProvision,
      hasLaunchError: hasLaunchError,
    );
    final overlay = resolveChatWorkbenchOverlay(
      workbenchView: workbenchView,
      sessionConnectInProgress: sessionConnectInProgress,
      showRemoteProvision: showRemoteProvision,
    );
    final showChat = overlay == ChatWorkbenchOverlay.chat;
    final showSessionStarting = overlay == ChatWorkbenchOverlay.sessionStarting;
    final failure = presentSessionLaunchFailure(launchError);
    final showTerminalLaunchError = shouldShowTerminalSessionLaunchErrorBanner(
      overlay: overlay,
      launchError: launchError,
      sessionConnectInProgress: sessionConnectInProgress,
    );
    final appSession = _resolveAppSession(chatCubit: chatCubit, slice: slice);
    final memberId = slice.selectedMemberId.isNotEmpty
        ? slice.selectedMemberId
        : _tabSelectedMemberId(chatCubit);
    final isPersonal =
        appSession?.sessionTeam.trim().isEmpty ?? isPersonalContext;
    final historyMemberId = isPersonal ? '' : memberId;
    final resolvedTeam = isPersonal
        ? null
        : (team ??
              (appSession != null
                  ? _teamProfileForSession(context, appSession)
                  : null));

    // Keep Alacritty mounted across title-bar workspace tab switches; hide with
    // [TpKeepAliveLayer] so scrollback survives without paying layout while
    // the tab is in the background. Also keep it mounted while Chat is shown
    // over a running PTY.
    final chatOverlayHidesTerminal =
        showSessionStarting || showChat || showRemoteProvision;
    return TpDeferredForegroundMount(
      active: terminalVisible,
      retainWhenInactive: true,
      builder: (context) => TpKeepAliveLayer(
        active: terminalVisible,
        child: TickerMode(
          enabled: terminalVisible,
          child: IgnorePointer(
            ignoring: !terminalVisible,
            child: Stack(
              key: kChatWorkbenchTerminalStackKey,
              fit: StackFit.expand,
              children: [
                if (mountTerminalForLayout)
                  TpKeepAliveLayer(
                    active: !chatOverlayHidesTerminal,
                    child: TickerMode(
                      enabled: !chatOverlayHidesTerminal,
                      child: buildRunningTerminal(
                        session: session,
                        terminalTheme: terminalTheme,
                        chatCubit: chatCubit,
                        isPersonal: isPersonalContext,
                        team: resolvedTeam,
                        appSession: appSession,
                        historyMemberId: historyMemberId,
                        autofocus: !chatOverlayHidesTerminal && terminalVisible,
                      ),
                    ),
                  ),
                if (showRemoteProvision)
                  ChatWorkbenchRemoteProvisionView(
                    progress: remoteProvision,
                    memberLabel: _memberDisplayLabel(
                      team: team,
                      memberId: remoteProvision.memberId,
                    ),
                  )
                else if (showChat)
                  _buildSessionChatView(
                    context,
                    chatCubit: chatCubit,
                    team: team,
                    launchError: launchError,
                    sessionConnectInProgress: sessionConnectInProgress,
                    viewToggle: dockedViewToggle,
                  )
                else if (showSessionStarting)
                  ChatWorkbenchSessionLoadingView(
                    message: context.l10n.sessionStarting,
                  ),
                if (workbenchView == SessionWorkbenchView.chat && !showChat)
                  // Chat view is not hosting the merged task-board capsule
                  // (remote provision / session starting) — float the toggle
                  // so the view switch stays reachable.
                  Positioned(
                    top: context.tpSpacing.sm,
                    right: context.tpSpacing.sm,
                    child: floatingViewToggle,
                  ),
                if (workbenchView == SessionWorkbenchView.terminal &&
                    !mountTerminalForLayout &&
                    overlay == ChatWorkbenchOverlay.none)
                  _buildTerminalPlaceholder(context, chatCubit: chatCubit),
                if (showTerminalLaunchError && failure != null)
                  Positioned(
                    // Below the floating Chat/Terminal capsule (top-right).
                    top: 48,
                    right: 0,
                    child: Material(
                      type: MaterialType.transparency,
                      child: Padding(
                        padding: EdgeInsets.all(context.tpSpacing.md),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 260),
                          child: SessionLaunchErrorBanner(
                            view: failure,
                            compact: true,
                            isRetrying: sessionConnectInProgress,
                            onRetry: () {
                              final id = slice.activeSessionId;
                              if (id == null || id.isEmpty) return;
                              unawaited(chatCubit.retrySessionLaunch(id));
                            },
                            onRemapDeadTarget:
                                deadSshTargetIdFromError(launchError) != null
                                ? () {
                                    final id = slice.activeSessionId;
                                    if (id == null || id.isEmpty) return;
                                    unawaited(
                                      onRemapDeadTargetFromLaunch(
                                        launchError: launchError!,
                                        sessionId: id,
                                      ),
                                    );
                                  }
                                : null,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _memberDisplayLabel({
    required TeamProfile? team,
    required String memberId,
  }) {
    final mid = memberId.trim();
    if (mid.isEmpty) return '';
    final member = team?.members.where((m) => m.id == mid).firstOrNull;
    if (member == null) return '';
    final name = member.name.trim();
    return name.isNotEmpty ? name : '';
  }

  /// Placeholder for a member terminal that is not running — either reclaimed
  /// for idle or never launched (lazy default). Tap restores it.
  Widget _buildTerminalPlaceholder(
    BuildContext context, {
    required ChatCubit chatCubit,
  }) {
    final sessionId = slice.activeSessionId;
    final memberId = slice.selectedMemberId;
    final reclaimed =
        sessionId != null &&
        memberId.isNotEmpty &&
        chatCubit.isMemberTerminalReclaimed(sessionId, memberId);
    final theme = Theme.of(context);
    return Center(
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _restoreTerminalFromPlaceholder(
          context,
          chatCubit: chatCubit,
          sessionId: sessionId,
          memberId: memberId,
        ),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                reclaimed ? Icons.restore_outlined : Icons.terminal_outlined,
                size: 40,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              Text(
                reclaimed
                    ? context.l10n.memberTerminalReclaimedTitle
                    : context.l10n.memberTerminalNotStartedTitle,
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              if (reclaimed) ...[
                const SizedBox(height: 4),
                Text(
                  context.l10n.memberTerminalReclaimedBody,
                  style: theme.textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _restoreTerminalFromPlaceholder(
    BuildContext context, {
    required ChatCubit chatCubit,
    required String? sessionId,
    required String memberId,
  }) {
    if (sessionId == null || sessionId.isEmpty) return;
    if (memberId.isEmpty) return;
    // Simple mode restores via the existing reconnect path; team members go
    // through the lazy-spawn funnel (resume).
    final appSession = _resolveAppSession(chatCubit: chatCubit, slice: slice);
    if (appSession?.sessionTeam.trim().isEmpty ?? true) {
      unawaited(chatCubit.retrySessionLaunch(sessionId));
    } else {
      unawaited(chatCubit.ensureMemberTerminalForView(sessionId, memberId));
    }
  }

  Widget _buildSessionChatView(
    BuildContext context, {
    required ChatCubit chatCubit,
    required TeamProfile? team,
    required String? launchError,
    required bool sessionConnectInProgress,
    required Widget viewToggle,
  }) {
    final appSession = _resolveAppSession(chatCubit: chatCubit, slice: slice);
    if (appSession == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final memberId = slice.selectedMemberId.isNotEmpty
        ? slice.selectedMemberId
        : _tabSelectedMemberId(chatCubit);

    final isPersonal = appSession.sessionTeam.trim().isEmpty;
    // Simple seats use sessionId as selectedMemberId for PTY shells; history
    // locate treats non-empty memberId as a team roster seat.
    final historyMemberId = isPersonal ? '' : memberId;
    final resolvedTeam = isPersonal
        ? null
        : (team ?? _teamProfileForSession(context, appSession));
    // Prefer session/runtime pods so numbered seats (developer-0) match the
    // Members panel — looking up team.members type ids alone retargeted Chat
    // continue to the team lead.
    final connectMember = (!isPersonal && resolvedTeam != null)
        ? resolveSessionChatContinueMember(
            session: appSession,
            team: resolvedTeam,
            selectedMemberId: memberId,
          )
        : null;
    final shellMemberId = isPersonal
        ? appSession.sessionId
        : (connectMember?.id ?? memberId);
    HistoryContinueChannel resolveChannel() {
      final bus = chatCubit.sessionRuntime.busForSession(appSession.sessionId);
      return resolveHistoryContinueChannel(
        teamBusInstalled: bus != null,
        memberWaitingForMessage:
            bus?.isWaitingForMessage(shellMemberId) ?? false,
        memberInTurn: bus?.isMemberInTurn(shellMemberId) ?? false,
      );
    }

    return SessionChatView(
      session: appSession,
      viewToggle: viewToggle,
      workspace:
          chatCubit.state.workspaces
              .where((w) => w.workspaceId == workspaceId)
              .firstOrNull ??
          Workspace(
            workspaceId: workspaceId,
            folders: appSession.folders,
            createdAt: 0,
          ),
      selectedMemberId: historyMemberId,
      team: resolvedTeam,
      routeActive: routeActive,
      launchError: launchError,
      sessionConnectInProgress: sessionConnectInProgress,
      onRetry: () =>
          unawaited(chatCubit.retrySessionLaunch(appSession.sessionId)),
      peekContinueChannel: resolveChannel,
      isMailboxUnread: (mailId) {
        final bus = chatCubit.sessionRuntime.busForSession(
          appSession.sessionId,
        );
        if (bus == null) return false;
        return bus.isUnread(shellMemberId, mailId);
      },
      onRemapDeadTarget: deadSshTargetIdFromError(launchError) != null
          ? () => unawaited(
              onRemapDeadTargetFromLaunch(
                launchError: launchError!,
                sessionId: appSession.sessionId,
              ),
            )
          : null,
      onSubmit: (message) async {
        final switchToTerminal = shouldSwitchToTerminalAfterChatSubmit(
          context
              .read<SessionPreferencesCubit>()
              .state
              .preferences
              .chatSubmitSwitchesToTerminal,
        );
        if (switchToTerminal) {
          chatCubit.setSessionWorkbenchView(
            appSession.sessionId,
            SessionWorkbenchView.terminal,
          );
        }
        context.read<WorkbenchCubit>().openSession(
          workspaceId,
          appSession.sessionId,
          preview: false,
        );
        final connectRequest = ExistingSessionConnect(
          session: appSession,
          team: resolvedTeam,
          member: connectMember,
          // Stay-on-Chat must not let connect force-switch to Terminal.
          preserveWorkbenchView: !switchToTerminal,
        );

        return chatCubit.withOperatorDeliveryInFlight(
          appSession.sessionId,
          () => submitSessionHistoryReviewMessage(
            sessionId: appSession.sessionId,
            memberId: shellMemberId,
            message: message,
            connectRequest: connectRequest,
            resolveChannel: resolveChannel,
            connectWorkspaceSession: chatCubit.connectWorkspaceSession,
            ensureMemberInputReady:
                (sessionId, mid, {bool directToPty = false}) =>
                    chatCubit.memberMaterializer.ensureMemberInputReady(
                      sessionId,
                      mid,
                      directToPty: directToPty,
                    ),
            deliverUserCommandToMember:
                (sessionId, mid, text, {bool directToPty = false}) =>
                    chatCubit.sessionRuntime.deliverUserCommandToMember(
                      sessionId,
                      mid,
                      text,
                      directToPty: directToPty,
                    ),
            applyFirstPromptTitle: chatCubit.applyFirstPromptTitle,
          ),
        );
      },
    );
  }

  TeamProfile? _teamProfileForSession(
    BuildContext context,
    AppSession session,
  ) {
    final teamId = session.sessionTeam.trim();
    if (teamId.isEmpty) return null;
    final profile = context.read<LaunchProfileCubit>().byId(teamId);
    return profile is TeamProfile ? profile : null;
  }

  String _tabSelectedMemberId(ChatCubit chatCubit) {
    final activeId = slice.activeSessionId;
    if (activeId == null) return '';
    for (final tab in chatCubit.tabStore.tabsForWorkspace(tabScopeId)) {
      if (tab.info.id == activeId) return tab.selectedMemberId;
    }
    return '';
  }
}
