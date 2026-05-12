import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:xterm/xterm.dart';

import '../cubits/chat_cubit.dart';
import '../cubits/team_cubit.dart';
import '../l10n/app_localizations.dart';
import '../services/terminal_session.dart';
import '../theme/app_theme.dart';
import '../utils/app_keys.dart';

class ChatWorkbench extends StatefulWidget {
  const ChatWorkbench({this.sessionId, super.key});

  final String? sessionId;

  @override
  State<ChatWorkbench> createState() => _ChatWorkbenchState();
}

class _ChatWorkbenchState extends State<ChatWorkbench> {
  static const _terminalTheme = TerminalTheme(
    cursor: Color(0xFFAEAFAD),
    selection: Color(0x40AEAFAD),
    foreground: Color(0xFFE0E0E0),
    background: Color(0xFF0A0C10),
    black: Color(0xFF1A1A1A),
    red: Color(0xFFE0556A),
    green: Color(0xFF5CCF8A),
    yellow: Color(0xFFE5C565),
    blue: Color(0xFF5BA4E6),
    magenta: Color(0xFFC88CE6),
    cyan: Color(0xFF56C5D0),
    white: Color(0xFFE5E5E5),
    brightBlack: Color(0xFF5A5A5A),
    brightRed: Color(0xFFFF7B8A),
    brightGreen: Color(0xFF7DE8A8),
    brightYellow: Color(0xFFFFE080),
    brightBlue: Color(0xFF80C0FF),
    brightMagenta: Color(0xFFE0A8FF),
    brightCyan: Color(0xFF80E0E8),
    brightWhite: Color(0xFFFFFFFF),
    searchHitBackground: Color(0xFFFFFF2B),
    searchHitBackgroundCurrent: Color(0xFF31FF26),
    searchHitForeground: Color(0xFF000000),
  );

  TerminalSession? _session;
  var _ensuredLocalSession = false;

  @override
  void initState() {
    super.initState();
    // If sessionId is provided, open it
    if (widget.sessionId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final chatCubit = context.read<ChatCubit>();
        final l10n = AppLocalizations.of(context);
        final sessions = chatCubit.state.sessions;
        final session = sessions.firstWhere(
          (s) => s.sessionId == widget.sessionId,
          orElse: () => sessions.first,
        );
        if (sessions.isNotEmpty) {
          chatCubit.openSessionTab(
            session,
            emptyDisplayTitleFallback: l10n.defaultNewChatSessionTitle,
          );
        }
      });
    }
    context.read<ChatCubit>().stream.listen(_onCubitChanged);
  }

  void _onCubitChanged(ChatState state) {
    if (!mounted) return;
    setState(() {
      _session = context.read<ChatCubit>().currentSession;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final teamCubit = context.watch<TeamCubit>();
    final chatCubit = context.read<ChatCubit>();
    final team = teamCubit.state.selectedTeam;

    if (team == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!_ensuredLocalSession && chatCubit.state.tabs.isEmpty) {
      _ensuredLocalSession = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<ChatCubit>().ensureSessionTab(team);
      });
    }

    _session ??= chatCubit.ensureSession(team);
    final session = _session!;

    return Container(
      key: AppKeys.chatWorkspace,
      color: colors.workspaceBackground,
      child: Column(
        children: [
          _TerminalToolbar(
            colors: colors,
            session: session,
            memberName: chatCubit.selectedMemberName(team),
            onConnect: () {
              chatCubit.connectSession(team);
              setState(() {});
            },
            onDisconnect: () {
              chatCubit.disconnectSession();
              setState(() {});
            },
            onRestart: () {
              chatCubit.restartSession(team);
              setState(() {
                _session = chatCubit.currentSession;
              });
            },
          ),
          Expanded(
            child: Container(
              color: const Color(0xFF0A0C10),
              child: session.isRunning
                  ? TerminalView(
                      session.terminal,
                      theme: _terminalTheme,
                      backgroundOpacity: 0.98,
                      padding: const EdgeInsets.all(16),
                      textStyle: const TerminalStyle(
                        fontSize: 14,
                        fontFamily: 'monospace',
                        fontFamilyFallback: [
                          'Ubuntu Mono',
                          'DejaVu Sans Mono',
                          'Liberation Mono',
                          'Noto Mono',
                          'Consolas',
                          'Courier New',
                          'HYZhongHei',
                          'Noto Color Emoji',
                          'monospace',
                        ],
                      ),
                      autofocus: true,
                    )
                  : _TerminalPlaceholder(
                      onConnect: () {
                        chatCubit.connectSession(team);
                        setState(() {});
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TerminalToolbar extends StatelessWidget {
  const _TerminalToolbar({
    required this.colors,
    required this.session,
    required this.memberName,
    required this.onConnect,
    required this.onDisconnect,
    required this.onRestart,
  });

  final AppColors colors;
  final TerminalSession session;
  final String memberName;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: colors.surfaceVariant,
        border: Border(bottom: BorderSide(color: colors.subtleBorder)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.terminal,
            size: 14,
            color: session.isRunning
                ? colors.accentGreen
                : colors.emptyMessageText,
          ),
          const SizedBox(width: 6),
          Text(
            session.isRunning ? 'flashskyai' : 'disconnected',
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withValues(alpha: 0.68),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '→ $memberName',
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withValues(alpha: 0.4),
            ),
          ),
          const Spacer(),
          if (session.isRunning) ...[
            SizedBox(
              height: 22,
              child: IconButton(
                tooltip: 'Disconnect',
                onPressed: onDisconnect,
                icon: const Icon(Icons.link_off, size: 14),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 22),
              ),
            ),
            const SizedBox(width: 4),
            SizedBox(
              height: 22,
              child: IconButton(
                tooltip: 'Restart session',
                onPressed: onRestart,
                icon: const Icon(Icons.refresh, size: 14),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 22),
              ),
            ),
          ] else
            SizedBox(
              height: 22,
              child: TextButton.icon(
                onPressed: onConnect,
                icon: const Icon(Icons.play_arrow, size: 14),
                label: const Text('Connect', style: TextStyle(fontSize: 11)),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 22),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TerminalPlaceholder extends StatelessWidget {
  const _TerminalPlaceholder({required this.onConnect});

  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.terminal,
            size: 48,
            color: textBase.withValues(alpha: 0.24),
          ),
          const SizedBox(height: 12),
          Text(
            'Terminal not connected',
            style: TextStyle(
              color: textBase.withValues(alpha: 0.54),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Connect to start a flashskyai session',
            style: TextStyle(
              color: textBase.withValues(alpha: 0.34),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onConnect,
            icon: const Icon(Icons.play_arrow, size: 16),
            label: const Text('Connect'),
          ),
        ],
      ),
    );
  }
}
