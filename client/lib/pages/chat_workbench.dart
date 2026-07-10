import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';

import '../cubits/chat/model/session_connect_request.dart';
import '../cubits/chat/model/chat_tab.dart';
import '../cubits/chat_cubit.dart';
import '../cubits/layout_cubit.dart';
import '../cubits/launch_profile_cubit.dart';
import '../cubits/session_preferences_cubit.dart';
import '../l10n/l10n_extensions.dart';
import '../models/app_session.dart';
import '../models/team_config.dart';
import '../repositories/session_repository.dart';
import '../services/terminal/terminal_session.dart';
import '../services/terminal/terminal_theme_mapper.dart';
import '../services/workbench/workbench_editor_opener.dart';
import '../theme/workspace_surface_layers.dart';
import '../utils/app_keys.dart';
import '../widgets/deferred_foreground_mount.dart';
import '../utils/team_member_naming.dart';
import 'home_workspace/workspace/workspace_route_active_scope.dart';
import 'chat/chat_workbench_placeholders.dart';
import 'chat/chat_workbench_slice.dart';
import 'chat/chat_workbench_terminal.dart';
import 'chat/session_history_review.dart';
import 'chat/session_history_review_submit.dart';

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
  var _handledRouteSession = false;
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
    await openChatWorkbenchTerminalLink(
      link: link,
      chatCubit: context.read<ChatCubit>(),
      editorOpener: context.read<WorkbenchEditorOpener>(),
      workspaceId: widget.workspaceId,
      isMounted: () => mounted,
    );
  }

  void _consumeRouteSession(ChatState state) {
    if (!mounted) return;
    final connectImmediately = context
        .read<SessionPreferencesCubit>()
        .state
        .preferences
        .openExistingSessionStartsTerminal;
    consumeChatWorkbenchRouteSession(
      routeSessionId: widget.sessionId,
      handledRouteSession: _handledRouteSession,
      state: state,
      chatCubit: context.read<ChatCubit>(),
      teamCubit: context.read<LaunchProfileCubit>(),
      sessionRepo: context.read<SessionRepository>(),
      l10n: AppLocalizations.of(context),
      onHandled: (handled) => _handledRouteSession = handled,
      connectImmediately: connectImmediately,
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
    return BlocListener<ChatCubit, ChatState>(
      listenWhen: (previous, next) =>
          widget.routeActive && widget.sessionId != null,
      listener: (context, state) => _consumeRouteSession(state),
      child: _ChatWorkbenchBody(
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
      ),
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
    required bool autofocus,
  })
  buildRunningTerminal;

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
    if (sessionId != null && slice.tabCount == 0) {
      return const Center(child: CircularProgressIndicator());
    } else if (slice.tabCount == 0) {
      return const Center(child: CircularProgressIndicator());
    }

    final sessionConnectInProgress = slice.isActiveSessionConnecting;

    final session = _resolveSession(
      chatCubit: chatCubit,
      slice: slice,
      team: team,
    );
    if (session == null) {
      return const Center(child: CircularProgressIndicator());
    }
    onSyncTerminalTheme(session, terminalTheme, slice.selectedMemberId);

    final launchError =
        routeActive &&
            chatCubit.tabStore.activeWorkspaceId == tabScopeId
        ? (chatCubit.activeLaunchError ?? slice.sessionLaunchError)
        : slice.sessionLaunchError;

    return Container(
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
          sessionConnectInProgress: sessionConnectInProgress,
          launchError: launchError,
        ),
      ),
    );
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
  }) {
    final routeForeground =
        routeActive && WorkspaceRouteActiveScope.routeActiveOf(context);
    final tickerActive = TickerMode.valuesOf(context).enabled;
    final terminalVisible = routeForeground && tickerActive;

    final mountTerminalForLayout =
        sessionConnectInProgress || session.isRunning;

    // Keep Alacritty mounted across title-bar workspace tab switches; hide with
    // [Offstage] so scrollback survives when the tab returns to foreground.
    return DeferredForegroundMount(
      active: terminalVisible,
      retainWhenInactive: true,
      builder: (context) => Offstage(
        offstage: !terminalVisible,
        child: IgnorePointer(
          ignoring: !terminalVisible,
          child: Stack(
            key: kChatWorkbenchTerminalStackKey,
            fit: StackFit.expand,
            children: [
              if (mountTerminalForLayout)
                Offstage(
                  offstage: sessionConnectInProgress,
                  child: buildRunningTerminal(
                    session: session,
                    terminalTheme: terminalTheme,
                    chatCubit: chatCubit,
                    isPersonal: isPersonalContext,
                    team: team,
                    autofocus: !sessionConnectInProgress && terminalVisible,
                  ),
                ),
              if (sessionConnectInProgress)
                ChatWorkbenchSessionLoadingView(
                  message: context.l10n.sessionStarting,
                )
              else if (!session.isRunning)
                _buildHistoryReview(
                  context,
                  chatCubit: chatCubit,
                  team: team,
                  launchError: launchError,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHistoryReview(
    BuildContext context, {
    required ChatCubit chatCubit,
    required TeamProfile? team,
    required String? launchError,
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
    TeamMemberConfig? connectMember;
    if (!isPersonal && resolvedTeam != null) {
      final mid = memberId.trim();
      if (mid.isNotEmpty) {
        connectMember = resolvedTeam.members
            .where((m) => m.id == mid)
            .firstOrNull;
      }
      connectMember ??= resolvedTeam.members
          .where((m) => TeamMemberNaming.isTeamLead(m))
          .firstOrNull;
      connectMember ??= resolvedTeam.members.firstOrNull;
    }
    final shellMemberId = isPersonal
        ? appSession.sessionId
        : (connectMember?.id ?? memberId);
    final connectRequest = ExistingSessionConnect(
      session: appSession,
      team: resolvedTeam,
      member: connectMember,
    );

    return SessionHistoryReview(
      session: appSession,
      selectedMemberId: historyMemberId,
      team: resolvedTeam,
      launchError: launchError,
      onSubmit: (message) => submitSessionHistoryReviewMessage(
        sessionId: appSession.sessionId,
        memberId: shellMemberId,
        message: message,
        connectRequest: connectRequest,
        connectWorkspaceSession: chatCubit.connectWorkspaceSession,
        ensureMemberInputReady:
            (sessionId, mid, {bool directToPty = false}) => chatCubit
                .memberMaterializer
                .ensureMemberInputReady(
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
  }

  TeamProfile? _teamProfileForSession(BuildContext context, AppSession session) {
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
