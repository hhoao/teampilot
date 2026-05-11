import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:xterm/xterm.dart';

import '../cubits/chat_cubit.dart';
import '../cubits/team_cubit.dart';
import '../services/terminal_session.dart';
import '../theme/app_theme.dart';
import '../utils/app_keys.dart';
import '../utils/perf.dart';

class ChatWorkbench extends StatefulWidget {
  const ChatWorkbench({this.sessionId, super.key});

  final String? sessionId;

  @override
  State<ChatWorkbench> createState() => _ChatWorkbenchState();
}

class _ChatWorkbenchState extends State<ChatWorkbench> {
  TerminalSession? _session;
  var _ensuredLocalSession = false;

  @override
  void initState() {
    super.initState();
    // If sessionId is provided, open it
    if (widget.sessionId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final chatCubit = context.read<ChatCubit>();
        final sessions = chatCubit.state.sessions;
        final session = sessions.firstWhere(
          (s) => s.sessionId == widget.sessionId,
          orElse: () => sessions.first,
        );
        if (sessions.isNotEmpty) {
          chatCubit.openSessionTab(session);
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
                  ? PipelinePerf(
                      label: 'terminal view',
                      child: BuildPerf(
                        label: 'terminal view',
                        builder: (_) => TerminalView(
                          session.terminal,
                          backgroundOpacity: 0.92,
                          padding: const EdgeInsets.all(6),
                          textStyle: const TerminalStyle(
                            fontFamily: 'monospace',
                            fontFamilyFallback: ['monospace'],
                          ),
                          autofocus: true,
                        ),
                      ),
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
