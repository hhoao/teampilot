import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/widgets/app_toast/app_toast.dart';

import '../cubits/chat/model/session_connect_request.dart';
import '../cubits/chat/model/chat_tab.dart';
import '../cubits/chat_cubit.dart';
import '../cubits/layout_cubit.dart';
import '../cubits/launch_profile_cubit.dart';
import '../cubits/session_preferences_cubit.dart';
import '../cubits/workbench/workbench_cubit.dart';
import '../cubits/workbench/workbench_tab.dart';
import '../l10n/l10n_extensions.dart';
import '../models/app_session.dart';
import '../models/team_config.dart';
import '../repositories/session_repository.dart';
import '../repositories/ssh_profile_repository.dart';
import '../services/storage/home_target_controller.dart';
import '../services/terminal/terminal_session.dart';
import '../services/terminal/terminal_theme_mapper.dart';
import '../services/workbench/workbench_editor_opener.dart';
import '../services/workspace/dead_ssh_target_error.dart';
import '../services/workspace/target_liveness.dart';
import '../theme/workspace_surface_layers.dart';
import '../utils/ui/app_keys.dart';
import '../widgets/workspace/workspace_dead_target_remap_dialog.dart';
import '../utils/team/team_member_naming.dart';
import 'home_workspace/workspace/workspace_route_active_scope.dart';
import 'chat/chat_workbench_overlay.dart';
import 'chat/chat_workbench_placeholders.dart';
import 'chat/chat_workbench_remote_provision_view.dart';
import 'chat/chat_workbench_slice.dart';
import 'chat/chat_workbench_terminal.dart';
import '../models/member_remote_provision_progress.dart';
import 'chat/history_continue_delivery.dart';
import 'chat/session_chat_view.dart';
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

  TargetLiveness _targetLiveness(BuildContext context) => DefaultTargetLiveness(
    sshProfiles: context.read<SshProfileRepository>(),
  );

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
      chat.invalidateWorkspaceProvision(updated);
      await chat.loadWorkspaceData(repo);
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
        onRemapDeadTargetFromLaunch: _remapDeadTargetFromLaunch,
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

    final workbenchView = context.select<ChatCubit, SessionWorkbenchView>((c) {
      final activeId = slice.activeSessionId;
      if (activeId == null || activeId.isEmpty) {
        return SessionWorkbenchView.chat;
      }
      final tab = c.tabStore.openTabBySessionId(activeId);
      return tab?.workbenchView ?? SessionWorkbenchView.chat;
    });

    final memberId = slice.selectedMemberId.isNotEmpty
        ? slice.selectedMemberId
        : '';
    final remoteProvision =
        context.select<ChatCubit, MemberRemoteProvisionProgress?>((c) {
          final activeId = slice.activeSessionId;
          if (activeId == null || activeId.isEmpty) return null;
          final mid = memberId.isNotEmpty
              ? memberId
              : c.tabStore.openTabBySessionId(activeId)?.selectedMemberId ??
                    '';
          if (mid.isEmpty) return null;
          return c.tabStore
              .openTabBySessionId(activeId)
              ?.memberRemoteProvision[mid];
        });

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
          workbenchView: workbenchView,
          remoteProvision: remoteProvision,
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
    required SessionWorkbenchView workbenchView,
    required MemberRemoteProvisionProgress? remoteProvision,
  }) {
    final routeForeground =
        routeActive && WorkspaceRouteActiveScope.routeActiveOf(context);
    final tickerActive = TickerMode.valuesOf(context).enabled;
    final terminalVisible = routeForeground && tickerActive;

    final showRemoteProvision =
        remoteProvision != null && !session.isRunning;
    final mountTerminalForLayout =
        sessionConnectInProgress || session.isRunning || showRemoteProvision;
    final overlay = resolveChatWorkbenchOverlay(
      workbenchView: workbenchView,
      sessionConnectInProgress: sessionConnectInProgress,
      showRemoteProvision: showRemoteProvision,
    );
    final showChat = overlay == ChatWorkbenchOverlay.chat;
    final showSessionStarting =
        overlay == ChatWorkbenchOverlay.sessionStarting;

    // Keep Alacritty mounted across title-bar workspace tab switches; hide with
    // [Offstage] so scrollback survives when the tab returns to foreground.
    // Also keep it mounted while Chat is shown over a running PTY.
    return TpDeferredForegroundMount(
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
                  offstage: showSessionStarting ||
                      showChat ||
                      showRemoteProvision,
                  child: buildRunningTerminal(
                    session: session,
                    terminalTheme: terminalTheme,
                    chatCubit: chatCubit,
                    isPersonal: isPersonalContext,
                    team: team,
                    autofocus: !showSessionStarting &&
                        !showChat &&
                        !showRemoteProvision &&
                        terminalVisible,
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
                )
              else if (showSessionStarting)
                ChatWorkbenchSessionLoadingView(
                  message: context.l10n.sessionStarting,
                ),
            ],
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
    if (mid.isEmpty) return mid;
    final member = team?.members.where((m) => m.id == mid).firstOrNull;
    if (member == null) return mid;
    final name = member.name.trim();
    return name.isNotEmpty ? name : mid;
  }

  Widget _buildSessionChatView(
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
      selectedMemberId: historyMemberId,
      team: resolvedTeam,
      launchError: launchError,
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
        context.read<WorkbenchCubit>().ensureTab(
          workspaceId,
          WorkbenchTabId.session(appSession.sessionId),
          preview: false,
        );
        final connectRequest = ExistingSessionConnect(
          session: appSession,
          team: resolvedTeam,
          member: connectMember,
          // Stay-on-Chat must not let connect force-switch to Terminal.
          preserveWorkbenchView: !switchToTerminal,
        );

        return submitSessionHistoryReviewMessage(
          sessionId: appSession.sessionId,
          memberId: shellMemberId,
          message: message,
          connectRequest: connectRequest,
          resolveChannel: resolveChannel,
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
        );
      },
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
