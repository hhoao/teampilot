import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:xterm/xterm.dart';

import '../cubits/chat_cubit.dart';
import '../cubits/team_cubit.dart';
import '../l10n/app_localizations.dart';
import '../models/app_session.dart';
import '../models/team_config.dart';
import '../repositories/session_repository.dart';
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
  final _terminalController = TerminalController();

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

  var _handledRouteSession = false;
  StreamSubscription<ChatState>? _chatSub;

  @override
  void initState() {
    super.initState();
    final chatCubit = context.read<ChatCubit>();
    _chatSub = chatCubit.stream.listen(_onChatState);
    _consumeRouteSession(chatCubit.state);
  }

  @override
  void dispose() {
    _terminalController.dispose();
    _chatSub?.cancel();
    super.dispose();
  }

  Future<void> _showTerminalContextMenu({
    required BuildContext menuContext,
    required Offset globalPosition,
    required Terminal terminal,
    required bool sessionRunning,
    required VoidCallback onDisconnect,
    required Future<void> Function() onRestart,
  }) async {
    final mloc = MaterialLocalizations.of(menuContext);
    final hasSelection = _terminalController.selection != null;
    final entries = <PopupMenuEntry<String>>[
      PopupMenuItem(value: 'paste', child: Text(mloc.pasteButtonLabel)),
      PopupMenuItem(
        value: 'copy',
        enabled: hasSelection,
        child: Text(mloc.copyButtonLabel),
      ),
      PopupMenuItem(value: 'selectAll', child: Text(mloc.selectAllButtonLabel)),
      const PopupMenuItem(
        value: 'clearSelection',
        child: Text('Clear selection'),
      ),
    ];
    if (sessionRunning) {
      entries.add(const PopupMenuDivider());
      entries.add(
        const PopupMenuItem(value: 'disconnect', child: Text('Disconnect')),
      );
      entries.add(
        const PopupMenuItem(value: 'restart', child: Text('Restart session')),
      );
    }

    final overlayObject =
        Overlay.maybeOf(menuContext)?.context.findRenderObject();
    if (overlayObject is! RenderBox) return;

    final anchor = overlayObject.globalToLocal(globalPosition);
    final selected = await showMenu<String>(
      context: menuContext,
      position: RelativeRect.fromRect(
        Rect.fromPoints(anchor, anchor),
        Offset.zero & overlayObject.size,
      ),
      items: entries,
    );
    if (!menuContext.mounted) return;
    switch (selected) {
      case 'paste':
        final data = await Clipboard.getData(Clipboard.kTextPlain);
        final text = data?.text;
        if (text != null && text.isNotEmpty) {
          terminal.paste(text);
          _terminalController.clearSelection();
        }
      case 'copy':
        final sel = _terminalController.selection;
        if (sel != null) {
          final text = terminal.buffer.getText(sel);
          await Clipboard.setData(ClipboardData(text: text));
        }
      case 'selectAll':
        _terminalController.setSelection(
          terminal.buffer.createAnchor(
            0,
            terminal.buffer.height - terminal.viewHeight,
          ),
          terminal.buffer.createAnchor(
            terminal.viewWidth,
            terminal.buffer.height - 1,
          ),
          mode: SelectionMode.line,
        );
      case 'clearSelection':
        _terminalController.clearSelection();
      case 'disconnect':
        onDisconnect();
      case 'restart':
        await onRestart();
      default:
        break;
    }
  }

  void _onChatState(ChatState state) {
    if (!mounted) return;
    setState(() {});
    _consumeRouteSession(state);
  }

  void _consumeRouteSession(ChatState state) {
    final routeId = widget.sessionId;
    if (routeId == null || _handledRouteSession || !mounted) return;

    AppSession? session;
    for (final s in state.sessions) {
      if (s.sessionId == routeId) {
        session = s;
        break;
      }
    }
    if (session == null) return;

    _handledRouteSession = true;
    final chatCubit = context.read<ChatCubit>();
    final teamCubit = context.read<TeamCubit>();
    final team = teamCubit.state.selectedTeam;
    final l10n = AppLocalizations.of(context);
    final repo = context.read<SessionRepository>();

    chatCubit.selectSession(session.sessionId);

    final lead = team != null
        ? team.members.where((m) => m.name == 'team-lead').toList()
        : <TeamMemberConfig>[];
    if (team != null && lead.isNotEmpty) {
      chatCubit.openSessionTab(
        session,
        team: team,
        member: lead.first,
        repo: repo,
        emptyDisplayTitleFallback: l10n.defaultNewChatSessionTitle,
      );
    } else {
      chatCubit.openSessionTab(
        session,
        repo: repo,
        emptyDisplayTitleFallback: l10n.defaultNewChatSessionTitle,
      );
      if (team != null) {
        chatCubit.addSystemMessage(
          'FlashskyAI requires a member named team-lead.',
        );
      }
    }
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

    if (widget.sessionId != null) {
      if (chatCubit.state.tabs.isEmpty) {
        return const Center(child: CircularProgressIndicator());
      }
    } else if (chatCubit.state.tabs.isEmpty) {
      void onConnect() {
        unawaited(() async {
          await chatCubit.connectSession(team);
          if (mounted) setState(() {});
        }());
      }

      return Container(
        key: AppKeys.chatWorkspace,
        color: colors.workspaceBackground,
        child: Column(
          children: [
            _NoSessionToolbar(
              colors: colors,
              memberName: chatCubit.selectedMemberName(team),
              onConnect: onConnect,
            ),
            Expanded(
              child: Container(
                color: const Color(0xFF0A0C10),
                child: _TerminalPlaceholder(onConnect: onConnect),
              ),
            ),
          ],
        ),
      );
    }

    final session = chatCubit.ensureSession(team) ?? chatCubit.currentSession;
    if (session == null) {
      return const Center(child: CircularProgressIndicator());
    }

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
              unawaited(() async {
                await chatCubit.connectSession(team);
                if (mounted) setState(() {});
              }());
            },
            onDisconnect: () {
              chatCubit.disconnectSession();
              setState(() {});
            },
            onRestart: () {
              unawaited(() async {
                await chatCubit.restartSession(team);
                if (mounted) {
                  setState(() {});
                }
              }());
            },
          ),
          Expanded(
            child: Container(
              color: const Color(0xFF0A0C10),
              child: session.isRunning
                  ? TerminalView(
                      session.terminal,
                      controller: _terminalController,
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
                      onSecondaryTapUp: (details, _) {
                        unawaited(
                          _showTerminalContextMenu(
                            menuContext: context,
                            globalPosition: details.globalPosition,
                            terminal: session.terminal,
                            sessionRunning: session.isRunning,
                            onDisconnect: () {
                              chatCubit.disconnectSession();
                              setState(() {});
                            },
                            onRestart: () async {
                              await chatCubit.restartSession(team);
                              if (mounted) setState(() {});
                            },
                          ),
                        );
                      },
                    )
                  : _TerminalPlaceholder(
                      onConnect: () {
                        unawaited(() async {
                          await chatCubit.connectSession(team);
                          if (mounted) setState(() {});
                        }());
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoSessionToolbar extends StatelessWidget {
  const _NoSessionToolbar({
    required this.colors,
    required this.memberName,
    required this.onConnect,
  });

  final AppColors colors;
  final String memberName;
  final VoidCallback onConnect;

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
            color: colors.emptyMessageText,
          ),
          const SizedBox(width: 6),
          Text(
            'disconnected',
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
