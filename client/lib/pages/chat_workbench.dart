import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';

import '../cubits/chat/model/session_connect_request.dart';
import '../cubits/chat_cubit.dart';
import '../cubits/editor_cubit.dart';
import '../cubits/layout_cubit.dart';
import '../cubits/launch_profile_cubit.dart';
import '../l10n/l10n_extensions.dart';
import '../models/team_config.dart';
import '../repositories/session_repository.dart';
import '../services/terminal/terminal_session.dart';
import '../services/terminal/terminal_theme_mapper.dart';
import '../theme/workspace_surface_layers.dart';
import '../utils/app_keys.dart';
import 'chat/chat_workbench_placeholders.dart';
import 'chat/chat_workbench_slice.dart';
import 'chat/chat_workbench_terminal.dart';

class ChatWorkbench extends StatefulWidget {
  const ChatWorkbench({
    required this.workspaceId,
    this.sessionId,
    this.isPersonalWorkspace = false,
    super.key,
  });

  final String workspaceId;
  final String? sessionId;
  final bool isPersonalWorkspace;

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
      editorCubit: context.read<EditorCubit>(),
      isMounted: () => mounted,
    );
  }

  void _consumeRouteSession(ChatState state) {
    if (!mounted) return;
    consumeChatWorkbenchRouteSession(
      routeSessionId: widget.sessionId,
      handledRouteSession: _handledRouteSession,
      state: state,
      chatCubit: context.read<ChatCubit>(),
      teamCubit: context.read<LaunchProfileCubit>(),
      sessionRepo: context.read<SessionRepository>(),
      l10n: AppLocalizations.of(context),
      onHandled: (handled) => _handledRouteSession = handled,
    );
  }

  SessionConnectRequest _connectRequest({required bool isPersonal, TeamProfile? team}) {
    if (isPersonal) {
      return PersonalSessionConnect(workspaceId: widget.workspaceId);
    }
    return TeamSessionConnect(team!);
  }

  Future<void> _connectWorkspace({
    required bool isPersonal,
    TeamProfile? team,
  }) async {
    await context.read<ChatCubit>().connectWorkspaceSession(
      _connectRequest(isPersonal: isPersonal, team: team),
      repo: context.read<SessionRepository>(),
    );
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
    return BlocListener<ChatCubit, ChatState>(
      listenWhen: (previous, next) => widget.sessionId != null,
      listener: (context, state) => _consumeRouteSession(state),
      child: BlocSelector<ChatCubit, ChatState, ChatWorkbenchSlice>(
        selector: ChatWorkbenchSlice.from,
        builder: (context, slice) {
          final team = widget.isPersonalWorkspace
              ? null
              : context.select<LaunchProfileCubit, TeamProfile?>(
                  (c) => c.state.selectedTeam,
                );
          return _ChatWorkbenchBody(
            workspaceId: widget.workspaceId,
            sessionId: widget.sessionId,
            isPersonalWorkspace: widget.isPersonalWorkspace,
            slice: slice,
            team: team,
            findVisible: _findVisible,
            onSyncTerminalTheme: _syncTerminalTheme,
            buildRunningTerminal: _buildRunningTerminal,
            onConnect: _connectWorkspace,
          );
        },
      ),
    );
  }
}

class _ChatWorkbenchBody extends StatelessWidget {
  const _ChatWorkbenchBody({
    required this.workspaceId,
    required this.sessionId,
    required this.isPersonalWorkspace,
    required this.slice,
    required this.team,
    required this.findVisible,
    required this.onSyncTerminalTheme,
    required this.buildRunningTerminal,
    required this.onConnect,
  });

  final String workspaceId;
  final String? sessionId;
  final bool isPersonalWorkspace;
  final ChatWorkbenchSlice slice;
  final TeamProfile? team;
  final bool findVisible;
  final void Function(TerminalSession, TerminalTheme, String) onSyncTerminalTheme;
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
    required bool isPersonal,
    TeamProfile? team,
  })
  onConnect;

  @override
  Widget build(BuildContext context) {
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
    final sessionConnectInProgress = slice.isActiveSessionConnecting;
    final launchError = chatCubit.activeLaunchError ?? slice.sessionLaunchError;

    if (!isPersonalWorkspace && team == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (sessionId != null) {
      if (slice.tabCount == 0) {
        return const Center(child: CircularProgressIndicator());
      }
    } else if (slice.tabCount == 0) {
      return Container(
        key: AppKeys.chatWorkspace,
        color: cs.surface,
        child: Container(
          color: terminalBackground,
          child: sessionConnectInProgress
              ? ChatWorkbenchSessionLoadingView(
                  message: context.l10n.sessionStarting,
                )
              : ChatWorkbenchTerminalPlaceholder(
                  onConnect: () => unawaited(
                    onConnect(isPersonal: isPersonalWorkspace, team: team),
                  ),
                  connectDisabled: sessionConnectInProgress,
                  memberName: isPersonalWorkspace
                      ? context.l10n.homeWorkspaceWorkspaceAgent
                      : chatCubit.selectedMemberName(team!),
                  launchError: launchError,
                ),
        ),
      );
    }

    final session = isPersonalWorkspace
        ? chatCubit.currentSession
        : (chatCubit.ensureSession(team!) ?? chatCubit.currentSession);
    if (session == null) {
      return const Center(child: CircularProgressIndicator());
    }
    onSyncTerminalTheme(session, terminalTheme, slice.selectedMemberId);

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

  Widget _buildTerminalBody(
    BuildContext context, {
    required TerminalSession session,
    required TerminalTheme terminalTheme,
    required ChatCubit chatCubit,
    required TeamProfile? team,
    required bool sessionConnectInProgress,
    required String? launchError,
  }) {
    final mountTerminalForLayout =
        sessionConnectInProgress || session.isRunning;

    return Stack(
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
              isPersonal: isPersonalWorkspace,
              team: team,
              autofocus: !sessionConnectInProgress,
            ),
          ),
        if (sessionConnectInProgress)
          ChatWorkbenchSessionLoadingView(
            message: context.l10n.sessionStarting,
          )
        else if (!session.isRunning)
          ChatWorkbenchTerminalPlaceholder(
            onConnect: () => unawaited(
              onConnect(isPersonal: isPersonalWorkspace, team: team),
            ),
            connectDisabled: sessionConnectInProgress,
            memberName: isPersonalWorkspace
                ? context.l10n.homeWorkspaceWorkspaceAgent
                : chatCubit.selectedMemberName(team!),
            launchError: launchError,
          ),
      ],
    );
  }
}
