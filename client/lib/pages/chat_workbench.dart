import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';

import '../cubits/chat_cubit.dart';
import '../cubits/editor_cubit.dart';
import '../cubits/layout_cubit.dart';
import '../cubits/team_cubit.dart';
import '../l10n/l10n_extensions.dart';
import '../models/team_config.dart';
import '../repositories/session_repository.dart';
import '../services/terminal/terminal_session.dart';
import '../services/terminal/terminal_theme_mapper.dart';
import '../utils/app_keys.dart';
import '../widgets/file_editor_panel.dart';
import 'chat/chat_workbench_placeholders.dart';
import 'chat/chat_workbench_terminal.dart';

class ChatWorkbench extends StatefulWidget {
  const ChatWorkbench({this.sessionId, super.key});

  final String? sessionId;

  @override
  State<ChatWorkbench> createState() => _ChatWorkbenchState();
}

class _ChatWorkbenchState extends State<ChatWorkbench> {
  TerminalController _terminalController = TerminalController();

  var _findVisible = false;
  var _handledRouteSession = false;
  StreamSubscription<ChatState>? _chatSub;
  int _lastWorkbenchStateVersion = -1;
  String? _lastActiveSessionId;
  String _lastSelectedMemberId = '';
  int _lastActiveTabIndex = -1;
  int _lastTabCount = -1;
  int? _lastTerminalThemeFingerprint;
  TerminalSession? _themeSyncedSession;
  String? _lastThemeSyncedMemberId;
  ChatCubit? _chatCubit;
  TeamCubit? _teamCubit;
  SessionRepository? _sessionRepo;
  EditorCubit? _editorCubit;

  @override
  void initState() {
    super.initState();
    final chatCubit = context.read<ChatCubit>();
    _chatCubit = chatCubit;
    _chatSub = chatCubit.stream.listen(_onChatState);
    _syncWorkbenchTracking(chatCubit.state);
    _consumeRouteSession(chatCubit.state);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _chatCubit = context.read<ChatCubit>();
    _teamCubit = context.read<TeamCubit>();
    _sessionRepo = context.read<SessionRepository>();
    _editorCubit = context.read<EditorCubit>();
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

  void _syncWorkbenchTracking(ChatState state) {
    _lastWorkbenchStateVersion = state.stateVersion;
    _lastActiveSessionId = state.activeSessionId;
    _lastSelectedMemberId = state.selectedMemberId;
    _lastActiveTabIndex = state.activeTabIndex;
    _lastTabCount = state.tabs.length;
  }

  bool _workbenchNeedsRebuild(ChatState state) {
    return state.stateVersion != _lastWorkbenchStateVersion ||
        state.activeSessionId != _lastActiveSessionId ||
        state.selectedMemberId != _lastSelectedMemberId ||
        state.activeTabIndex != _lastActiveTabIndex ||
        state.tabs.length != _lastTabCount;
  }

  @override
  void dispose() {
    _terminalController.dispose();
    _chatSub?.cancel();
    super.dispose();
  }

  Future<void> _openTerminalLink(String link) async {
    if (!mounted) return;
    final chatCubit = _chatCubit;
    final editorCubit = _editorCubit;
    if (chatCubit == null || editorCubit == null) return;
    await openChatWorkbenchTerminalLink(
      link: link,
      chatCubit: chatCubit,
      editorCubit: editorCubit,
      isMounted: () => mounted,
    );
  }

  void _onChatState(ChatState state) {
    if (!mounted) return;
    if (_workbenchNeedsRebuild(state)) {
      _syncWorkbenchTracking(state);
      setState(() {});
    }
    _consumeRouteSession(state);
  }

  void _consumeRouteSession(ChatState state) {
    final chatCubit = _chatCubit;
    final teamCubit = _teamCubit;
    final repo = _sessionRepo;
    if (chatCubit == null || teamCubit == null || repo == null || !mounted) {
      return;
    }
    consumeChatWorkbenchRouteSession(
      routeSessionId: widget.sessionId,
      handledRouteSession: _handledRouteSession,
      state: state,
      chatCubit: chatCubit,
      teamCubit: teamCubit,
      sessionRepo: repo,
      l10n: AppLocalizations.of(context),
      onHandled: (handled) => _handledRouteSession = handled,
    );
  }

  Future<void> _connectSession(TeamConfig team) async {
    final chatCubit = _chatCubit;
    if (chatCubit == null) return;
    await chatCubit.connectSession(team);
    if (mounted) setState(() {});
  }

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
    );
    final terminalBackground = Color(0xFF000000 | terminalTheme.background);
    final teamCubit = context.watch<TeamCubit>();
    final chatCubit = context.watch<ChatCubit>();
    final team = teamCubit.state.selectedTeam;
    final sessionConnectInProgress = chatCubit.state.isActiveSessionConnecting;

    if (team == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (widget.sessionId != null) {
      if (chatCubit.state.tabs.isEmpty) {
        return const Center(child: CircularProgressIndicator());
      }
    } else if (chatCubit.state.tabs.isEmpty) {
      return Container(
        key: AppKeys.chatWorkspace,
        color: cs.surface,
        child: WorkspaceEditorOverlay(
          terminalChild: Container(
            color: terminalBackground,
            child: sessionConnectInProgress
                ? ChatWorkbenchSessionLoadingView(
                    message: context.l10n.sessionStarting,
                  )
                : ChatWorkbenchTerminalPlaceholder(
                    onConnect: () => unawaited(_connectSession(team)),
                    connectDisabled: sessionConnectInProgress,
                    memberName: chatCubit.selectedMemberName(team),
                    launchError: chatCubit.activeLaunchError,
                  ),
          ),
        ),
      );
    }

    final session = chatCubit.ensureSession(team) ?? chatCubit.currentSession;
    if (session == null) {
      return const Center(child: CircularProgressIndicator());
    }
    _syncTerminalTheme(
      session,
      terminalTheme,
      chatCubit.state.selectedMemberId,
    );

    return Container(
      key: AppKeys.chatWorkspace,
      color: cs.surface,
      child: WorkspaceEditorOverlay(
        terminalChild: Container(
          color: terminalBackground,
          child: sessionConnectInProgress
              ? ChatWorkbenchSessionLoadingView(
                  message: context.l10n.sessionStarting,
                )
              : session.isRunning
              ? () {
                  _terminalController = bindChatWorkbenchTerminalController(
                    _terminalController,
                    session.engine,
                  );
                  return ChatWorkbenchRunningTerminal(
                    session: session,
                    terminalTheme: terminalTheme,
                    terminalController: _terminalController,
                    findVisible: _findVisible,
                    onFindVisibleChanged: (visible) =>
                        setState(() => _findVisible = visible),
                    onControllerSearchChanged: () => setState(() {}),
                    onOpenLink: _openTerminalLink,
                    onDisconnect: () {
                      chatCubit.disconnectSession();
                      setState(() {});
                    },
                    onRestart: () async {
                      await chatCubit.restartSession(team);
                      if (mounted) setState(() {});
                    },
                  );
                }()
              : ChatWorkbenchTerminalPlaceholder(
                  onConnect: () => unawaited(_connectSession(team)),
                  connectDisabled: sessionConnectInProgress,
                  memberName: chatCubit.selectedMemberName(team),
                  launchError: chatCubit.activeLaunchError,
                ),
        ),
      ),
    );
  }
}
