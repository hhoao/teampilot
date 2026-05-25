import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:xterm/xterm.dart';

import '../cubits/chat_cubit.dart';
import '../cubits/layout_cubit.dart';
import '../cubits/team_cubit.dart';
import '../l10n/l10n_extensions.dart';
import '../models/app_session.dart';
import '../models/team_config.dart';
import '../repositories/session_repository.dart';
import '../services/terminal_export.dart';
import '../services/terminal_uri_opener.dart';
import '../services/terminal_fonts.dart';
import '../utils/app_keys.dart';
import '../widgets/terminal_find_bar.dart';

const _terminalTextStyle = TerminalStyle(
  fontSize: 13,
  fontFamily: kTerminalFontFamily,
  height: 1.3,
  // Match VTE: ANSI bold uses brighter colors, not a heavier font file.
  useBoldFontWeight: false,
  fontFamilyFallback: [kUbuntuSansMonoFontFamily, 'monospace'],
);

TerminalTheme _terminalThemeFor(
  ColorScheme cs, {
  required bool isDark,
  required String mode,
}) {
  if (mode == 'classicDark') {
    return const TerminalTheme(
      cursor: Color(0xFF9AA0A8),
      selection: Color(0x409AA0A8),
      foreground: Color(0xFFC8CCD4),
      background: Color(0xFF0A0C10),
      black: Color(0xFF1A1A1A),
      red: Color(0xFFD04A62),
      green: Color(0xFF52C07E),
      yellow: Color(0xFFD4B85A),
      blue: Color(0xFF5298D8),
      magenta: Color(0xFFB87CD8),
      cyan: Color(0xFF4EB8C4),
      white: Color(0xFFD0D4DC),
      brightBlack: Color(0xFF5A5A5A),
      brightRed: Color(0xFFE86A7E),
      brightGreen: Color(0xFF6CD898),
      brightYellow: Color(0xFFE8CC70),
      brightBlue: Color(0xFF72B0E8),
      brightMagenta: Color(0xFFD098F0),
      brightCyan: Color(0xFF72D0DC),
      brightWhite: Color(0xFFE4E6EC),
      searchHitBackground: Color(0xFFFFFF2B),
      searchHitBackgroundCurrent: Color(0xFF31FF26),
      searchHitForeground: Color(0xFF000000),
    );
  }

  if (mode == 'highContrast') {
    final bg = isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF);
    final fg = isDark ? const Color(0xFFF5F7FA) : const Color(0xFF111111);
    final primary = isDark ? const Color(0xFF69B3FF) : const Color(0xFF005FCC);
    final secondary = isDark ? const Color(0xFF4EE2A8) : const Color(0xFF007A4B);
    return TerminalTheme(
      cursor: primary,
      selection: primary.withValues(alpha: 0.35),
      foreground: fg,
      background: bg,
      black: isDark ? const Color(0xFF1A1A1A) : const Color(0xFF2A2A2A),
      red: isDark ? const Color(0xFFFF6B7A) : const Color(0xFFB00020),
      green: secondary,
      yellow: isDark ? const Color(0xFFFFD166) : const Color(0xFF8A6D00),
      blue: primary,
      magenta: isDark ? const Color(0xFFD79BFF) : const Color(0xFF7A3DB8),
      cyan: isDark ? const Color(0xFF63E6FF) : const Color(0xFF006A85),
      white: fg,
      brightBlack: isDark ? const Color(0xFF8C8C8C) : const Color(0xFF666666),
      brightRed: isDark ? const Color(0xFFFF98A3) : const Color(0xFFD32F2F),
      brightGreen: isDark ? const Color(0xFF8AF0C6) : const Color(0xFF0A8F5A),
      brightYellow: isDark ? const Color(0xFFFFE08A) : const Color(0xFFA88700),
      brightBlue: isDark ? const Color(0xFF9CCEFF) : const Color(0xFF1976D2),
      brightMagenta: isDark ? const Color(0xFFE7C0FF) : const Color(0xFF9C4DCC),
      brightCyan: isDark ? const Color(0xFF9CEEFF) : const Color(0xFF008DB3),
      brightWhite: isDark ? const Color(0xFFFFFFFF) : const Color(0xFF000000),
      searchHitBackground: const Color(0xFFFFFF2B),
      searchHitBackgroundCurrent: const Color(0xFF31FF26),
      searchHitForeground: const Color(0xFF000000),
    );
  }

  final baseBackground = isDark
      ? Color.alphaBlend(cs.surface.withValues(alpha: 0.88), const Color(0xFF06080C))
      : Color.alphaBlend(cs.surface.withValues(alpha: 0.96), const Color(0xFFF7F9FC));
  final foreground = isDark ? const Color(0xFFC8CCD4) : const Color(0xFF1F2937);
  final weak = isDark ? const Color(0xFF59606A) : const Color(0xFF9AA3B2);
  return TerminalTheme(
    cursor: cs.primary.withValues(alpha: isDark ? 0.95 : 0.9),
    selection: cs.primary.withValues(alpha: isDark ? 0.28 : 0.2),
    foreground: foreground,
    background: baseBackground,
    black: isDark ? const Color(0xFF161A21) : const Color(0xFF4B5563),
    red: cs.error,
    green: cs.secondary,
    yellow: Color.lerp(cs.secondary, const Color(0xFFE5B95C), 0.5)!,
    blue: cs.primary,
    magenta: Color.lerp(cs.primary, cs.secondary, 0.45)!,
    cyan: Color.lerp(cs.secondary, const Color(0xFF58C8D7), 0.55)!,
    white: isDark ? const Color(0xFFD8DCE5) : const Color(0xFF374151),
    brightBlack: weak,
    brightRed: Color.lerp(cs.error, Colors.white, isDark ? 0.18 : 0.1)!,
    brightGreen: Color.lerp(cs.secondary, Colors.white, isDark ? 0.16 : 0.08)!,
    brightYellow: Color.lerp(
      Color.lerp(cs.secondary, const Color(0xFFE5B95C), 0.5)!,
      Colors.white,
      isDark ? 0.2 : 0.1,
    )!,
    brightBlue: Color.lerp(cs.primary, Colors.white, isDark ? 0.16 : 0.08)!,
    brightMagenta: Color.lerp(
      Color.lerp(cs.primary, cs.secondary, 0.45)!,
      Colors.white,
      isDark ? 0.2 : 0.1,
    )!,
    brightCyan: Color.lerp(
      Color.lerp(cs.secondary, const Color(0xFF58C8D7), 0.55)!,
      Colors.white,
      isDark ? 0.2 : 0.1,
    )!,
    brightWhite: isDark ? const Color(0xFFF2F4F8) : const Color(0xFF111827),
    searchHitBackground: const Color(0xFFFFFF2B),
    searchHitBackgroundCurrent: const Color(0xFF31FF26),
    searchHitForeground: const Color(0xFF000000),
  );
}

class ChatWorkbench extends StatefulWidget {
  const ChatWorkbench({this.sessionId, super.key});

  final String? sessionId;

  @override
  State<ChatWorkbench> createState() => _ChatWorkbenchState();
}

class _ChatWorkbenchState extends State<ChatWorkbench> {
  final _terminalController = TerminalController();

  var _findVisible = false;
  var _handledRouteSession = false;
  StreamSubscription<ChatState>? _chatSub;
  int _lastWorkbenchStateVersion = -1;
  String? _lastActiveSessionId;
  String _lastSelectedMemberId = '';
  int _lastActiveTabIndex = -1;
  int _lastTabCount = -1;

  @override
  void initState() {
    super.initState();
    final chatCubit = context.read<ChatCubit>();
    _chatSub = chatCubit.stream.listen(_onChatState);
    _syncWorkbenchTracking(chatCubit.state);
    _consumeRouteSession(chatCubit.state);
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

  Future<void> _showTerminalContextMenu({
    required BuildContext menuContext,
    required Offset globalPosition,
    required Terminal terminal,
    required CellOffset? cellOffset,
    required bool sessionRunning,
    required VoidCallback onDisconnect,
    required Future<void> Function() onRestart,
  }) async {
    final mloc = MaterialLocalizations.of(menuContext);
    final hasSelection = _terminalController.selection != null;
    final linkUri =
        cellOffset != null ? terminal.linkUriAt(cellOffset) : null;
    final entries = <PopupMenuEntry<String>>[
      PopupMenuItem(value: 'find', child: Text(context.l10n.terminalFind)),
      if (linkUri != null)
        PopupMenuItem(
          value: 'openLink',
          child: Text(context.l10n.terminalOpenLink),
        ),
      PopupMenuItem(
        value: 'export',
        child: Text(context.l10n.terminalExportScrollback),
      ),
      const PopupMenuDivider(),
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

    final overlayObject = Overlay.maybeOf(
      menuContext,
    )?.context.findRenderObject();
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
      case 'find':
        setState(() => _findVisible = true);
      case 'openLink':
        if (linkUri != null) {
          await TerminalUriOpener.open(linkUri);
        }
      case 'export':
        await _exportTerminalScrollback(menuContext, terminal);
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

  Future<void> _exportTerminalScrollback(
    BuildContext context,
    Terminal terminal,
  ) async {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: context.l10n.terminalExportScrollback,
      fileName: 'terminal-scrollback.txt',
      type: FileType.custom,
      allowedExtensions: ['txt'],
    );
    if (path == null || !context.mounted) return;
    await File(path).writeAsString(exportTerminalScrollback(terminal));
  }

  Future<void> _openLinkAt(Terminal terminal, CellOffset offset) async {
    final link = terminal.linkUriAt(offset);
    if (link == null) return;
    await TerminalUriOpener.open(link);
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
      unawaited(
        chatCubit.openSessionTab(
          session,
          team: team,
          member: lead.first,
          repo: repo,
          emptyDisplayTitleFallback: l10n.defaultNewChatSessionTitle,
        ),
      );
    } else {
      unawaited(
        chatCubit.openSessionTab(
          session,
          repo: repo,
          emptyDisplayTitleFallback: l10n.defaultNewChatSessionTitle,
        ),
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
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final terminalThemeMode = context.select<LayoutCubit, String>(
      (cubit) => cubit.state.preferences.terminalThemeMode,
    );
    final terminalTheme = _terminalThemeFor(
      cs,
      isDark: isDark,
      mode: terminalThemeMode,
    );
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
      void onConnect() {
        unawaited(() async {
          await chatCubit.connectSession(team);
          if (mounted) setState(() {});
        }());
      }

      return Container(
        key: AppKeys.chatWorkspace,
        color: cs.surface,
        child: Container(
          color: terminalTheme.background,
          child: sessionConnectInProgress
              ? _SessionLoadingView(message: context.l10n.sessionStarting)
              : _TerminalPlaceholder(
                  onConnect: onConnect,
                  memberName: chatCubit.selectedMemberName(team),
                ),
        ),
      );
    }

    final session = chatCubit.ensureSession(team) ?? chatCubit.currentSession;
    if (session == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Container(
      key: AppKeys.chatWorkspace,
      color: cs.surface,
      child: Container(
        color: terminalTheme.background,
        child: sessionConnectInProgress
            ? _SessionLoadingView(message: context.l10n.sessionStarting)
            : session.isRunning
            ? TerminalFindShortcuts(
                findVisible: _findVisible,
                onToggleFind: () => setState(() => _findVisible = true),
                onFindNext: () {
                  session.terminal.search.next();
                  _terminalController.setSearchResults(
                    session.terminal.search.hits,
                    activeIndex: session.terminal.search.currentIndex,
                  );
                },
                onFindPrevious: () {
                  session.terminal.search.previous();
                  _terminalController.setSearchResults(
                    session.terminal.search.hits,
                    activeIndex: session.terminal.search.currentIndex,
                  );
                },
                onCloseFind: () {
                  session.terminal.search.clear();
                  _terminalController.clearSearch();
                  setState(() => _findVisible = false);
                },
                child: Stack(
                  children: [
                    TerminalView(
                      session.terminal,
                      controller: _terminalController,
                      theme: terminalTheme,
                      backgroundOpacity: 0.98,
                      padding: const EdgeInsets.all(16),
                      textStyle: _terminalTextStyle,
                      autofocus: !_findVisible,
                      onTapUp: (details, offset) {
                        // Plain click selects text; Ctrl/⌘+click opens links.
                        if (HardwareKeyboard.instance.isControlPressed ||
                            HardwareKeyboard.instance.isMetaPressed) {
                          unawaited(_openLinkAt(session.terminal, offset));
                        } else {
                          _terminalController.clearSelection();
                        }
                      },
                      onSecondaryTapUp: (details, offset) {
                        unawaited(
                          _showTerminalContextMenu(
                            menuContext: context,
                            globalPosition: details.globalPosition,
                            terminal: session.terminal,
                            cellOffset: offset,
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
                    ),
                    if (_findVisible)
                      Positioned(
                        left: 8,
                        right: 8,
                        top: 8,
                        child: TerminalFindBar(
                          terminal: session.terminal,
                          controller: _terminalController,
                          searchLabel: context.l10n.terminalFind,
                          noResultsLabel: context.l10n.terminalFindNoResults,
                          onClose: () {
                            session.terminal.search.clear();
                            _terminalController.clearSearch();
                            setState(() => _findVisible = false);
                          },
                        ),
                      ),
                  ],
                ),
              )
            : _TerminalPlaceholder(
                onConnect: () {
                  unawaited(() async {
                    await chatCubit.connectSession(team);
                    if (mounted) setState(() {});
                  }());
                },
                memberName: chatCubit.selectedMemberName(team),
              ),
      ),
    );
  }
}

class _SessionLoadingView extends StatelessWidget {
  const _SessionLoadingView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 36,
            height: 36,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              color: textBase.withValues(alpha: 0.68),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _TerminalPlaceholder extends StatelessWidget {
  const _TerminalPlaceholder({
    required this.onConnect,
    this.memberName,
  });

  final VoidCallback onConnect;
  final String? memberName;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final member = memberName?.trim();
    final subtitle = member != null && member.isNotEmpty
        ? l10n.sessionReadySubtitle(member)
        : l10n.sessionReadySubtitleGeneric;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Color.alphaBlend(
                    cs.primary.withValues(alpha: 0.12),
                    cs.surfaceContainerHighest,
                  ),
                  shape: BoxShape.circle,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Icon(
                    Icons.forum_outlined,
                    size: 40,
                    color: cs.primary,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                l10n.sessionReadyTitle,
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                subtitle,
                style: textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  height: 1.45,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                l10n.sessionReadyHint,
                style: textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: onConnect,
                icon: const Icon(Icons.play_arrow_rounded, size: 22),
                label: Text(l10n.sessionStartButton),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 14,
                  ),
                  minimumSize: const Size(0, 48),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
