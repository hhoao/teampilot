import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:flutter_alacritty/input/paste.dart' as alacritty_paste;

import '../cubits/chat_cubit.dart';
import '../cubits/editor_cubit.dart';
import '../cubits/layout_cubit.dart';
import '../cubits/team_cubit.dart';
import '../l10n/l10n_extensions.dart';
import '../models/app_session.dart';
import '../models/team_config.dart';
import '../repositories/session_repository.dart';
import '../services/terminal/terminal_export.dart';
import '../services/terminal/terminal_session.dart';
import '../services/terminal/terminal_theme_mapper.dart';
import '../services/terminal/terminal_uri_opener.dart';
import '../services/terminal/terminal_fonts.dart';
import '../utils/app_keys.dart';
import '../utils/context_menu_position.dart';
import '../utils/debounce/debounce.dart';
import '../theme/app_text_styles.dart';
import '../widgets/file_editor_panel.dart';
import '../widgets/terminal_find_bar.dart';

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

  @override
  void initState() {
    super.initState();
    final chatCubit = context.read<ChatCubit>();
    _chatSub = chatCubit.stream.listen(_onChatState);
    _syncWorkbenchTracking(chatCubit.state);
    _consumeRouteSession(chatCubit.state);
  }

  /// [TerminalController.attach] is one-shot; re-bind when the active session's
  /// [TerminalEngine] instance changes (tab switch, reconnect, new shell).
  void _bindTerminalController(TerminalEngine engine) {
    if (identical(_terminalController.engine, engine)) return;
    if (_terminalController.engine != null) {
      _terminalController.dispose();
      _terminalController = TerminalController();
    }
    _terminalController.attach(engine);
  }

  /// Engine palette must match [terminalTheme]; [TerminalView.theme] alone does not
  /// recolor PTY output (unlike the old xterm [Terminal] theme).
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

  Future<void> _showTerminalContextMenu({
    required BuildContext menuContext,
    required Offset globalPosition,
    required TerminalEngine engine,
    required CellOffset? cellOffset,
    required bool sessionRunning,
    required VoidCallback onDisconnect,
    required Future<void> Function() onRestart,
  }) async {
    final mloc = MaterialLocalizations.of(menuContext);
    final hasSelection = _terminalController.selectionActive;
    final linkUri = cellOffset != null
        ? engine.hyperlinkAt(cellOffset.row, cellOffset.column)
        : null;
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

    final selected = await showMenu<String>(
      context: menuContext,
      position: contextMenuPositionForGlobal(menuContext, globalPosition),
      useRootNavigator: true,
      popUpAnimationStyle: const AnimationStyle(duration: Duration.zero),
      items: entries,
    );
    if (!menuContext.mounted) return;
    switch (selected) {
      case 'find':
        setState(() => _findVisible = true);
      case 'openLink':
        if (linkUri != null) {
          await _openTerminalLink(linkUri);
        }
      case 'export':
        await _exportTerminalScrollback(menuContext, engine);
      case 'paste':
        final data = await Clipboard.getData(Clipboard.kTextPlain);
        final text = data?.text;
        if (text != null && text.isNotEmpty) {
          _terminalController.onTerminalInputStart();
          engine.write(
            alacritty_paste.pasteBytes(text, modeFlags: engine.grid.modeFlags),
          );
          _terminalController.clearSelection();
        }
      case 'copy':
        final text = _terminalController.readSelectionText();
        if (text != null && text.isNotEmpty) {
          await Clipboard.setData(ClipboardData(text: text));
        }
      case 'selectAll':
        final grid = engine.grid;
        if (grid.rows > 0 && grid.columns > 0) {
          _terminalController.selectionStart(0, 0, false, 0);
          _terminalController.selectionUpdate(
            grid.rows - 1,
            grid.columns - 1,
            false,
          );
        }
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
    TerminalEngine engine,
  ) async {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: context.l10n.terminalExportScrollback,
      fileName: 'terminal-scrollback.txt',
      type: FileType.custom,
      allowedExtensions: ['txt'],
    );
    if (path == null || !context.mounted) return;
    await File(path).writeAsString(exportTerminalScrollback(engine));
  }

  Future<void> _openTerminalLink(String link) async {
    if (!mounted) return;
    final workingDirectory = context
        .read<ChatCubit>()
        .activeTabWorkingDirectory;
    await TerminalUriOpener.open(
      link,
      workingDirectory: workingDirectory,
      openInEditor: (path) async {
        await context.read<EditorCubit>().openFile(path);
      },
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
        ? team.members.where((m) => m.id == 'team-lead').toList()
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
      void onConnect() {
        unawaited(() async {
          await chatCubit.connectSession(team);
          if (mounted) setState(() {});
        }());
      }

      return Container(
        key: AppKeys.chatWorkspace,
        color: cs.surface,
        child: WorkspaceEditorOverlay(
          terminalChild: Container(
            color: terminalBackground,
            child: sessionConnectInProgress
                ? _SessionLoadingView(message: context.l10n.sessionStarting)
                : _TerminalPlaceholder(
                    onConnect: onConnect,
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
              ? _SessionLoadingView(message: context.l10n.sessionStarting)
              : session.isRunning
              ? () {
                  _bindTerminalController(session.engine);
                  return TerminalFindShortcuts(
                    findVisible: _findVisible,
                    onToggleFind: () => setState(() => _findVisible = true),
                    onFindNext: () {
                      _terminalController.searchNext();
                      setState(() {});
                    },
                    onFindPrevious: () {
                      _terminalController.searchPrev();
                      setState(() {});
                    },
                    onCloseFind: () {
                      _terminalController.searchClear();
                      setState(() => _findVisible = false);
                    },
                    child: Stack(
                      children: [
                        TerminalView(
                          session.engine,
                          controller: _terminalController,
                          theme: terminalTheme,
                          backgroundOpacity: 0.98,
                          padding: const EdgeInsets.all(16),
                          textStyle: appTerminalTextStyle(context),
                          autofocus: !_findVisible,
                          onViewportResize: session.onViewportResize,
                          onTapDown: (_, offset) {
                            if (!HardwareKeyboard.instance.isControlPressed &&
                                !HardwareKeyboard.instance.isMetaPressed) {
                              _terminalController.clearSelection();
                            }
                          },
                          onLinkActivate: (uri) {
                            unawaited(_openTerminalLink(uri));
                          },
                          onSecondaryTapDown: (details, offset) {
                            unawaited(
                              _showTerminalContextMenu(
                                menuContext: context,
                                globalPosition: details.globalPosition,
                                engine: session.engine,
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
                              engine: session.engine,
                              controller: _terminalController,
                              searchLabel: context.l10n.terminalFind,
                              noResultsLabel:
                                  context.l10n.terminalFindNoResults,
                              onClose: () {
                                _terminalController.searchClear();
                                setState(() => _findVisible = false);
                              },
                            ),
                          ),
                      ],
                    ),
                  );
                }()
              : _TerminalPlaceholder(
                  onConnect: () {
                    unawaited(() async {
                      await chatCubit.connectSession(team);
                      if (mounted) setState(() {});
                    }());
                  },
                  connectDisabled: sessionConnectInProgress,
                  memberName: chatCubit.selectedMemberName(team),
                  launchError: chatCubit.activeLaunchError,
                ),
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
            style: AppTextStyles.of(
              context,
            ).body.copyWith(color: textBase.withValues(alpha: 0.68)),
          ),
        ],
      ),
    );
  }
}

class _TerminalPlaceholder extends StatelessWidget {
  const _TerminalPlaceholder({
    required this.onConnect,
    this.connectDisabled = false,
    this.memberName,
    this.launchError,
  });

  final VoidCallback onConnect;
  final bool connectDisabled;
  final String? memberName;
  final String? launchError;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final member = memberName?.trim();
    final error = launchError?.trim();
    final hasError = error != null && error.isNotEmpty;
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
                hasError ? l10n.sessionFailedTitle : l10n.sessionReadyTitle,
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: hasError ? cs.error : null,
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
              if (hasError) ...[
                const SizedBox(height: 16),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: cs.errorContainer.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: cs.error.withValues(alpha: 0.35)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Text(
                      error,
                      style: textTheme.bodySmall?.copyWith(
                        color: cs.onErrorContainer,
                        height: 1.5,
                      ),
                      textAlign: TextAlign.start,
                    ),
                  ),
                ),
              ],
              if (!hasError) ...[
                const SizedBox(height: 12),
                Text(
                  l10n.sessionReadyHint,
                  style: textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: connectDisabled
                    ? null
                    : throttledOnPressed(
                        'chat_workbench_session_start',
                        onConnect,
                      ),
                icon: Icon(
                  hasError ? Icons.refresh_rounded : Icons.play_arrow_rounded,
                  size: 22,
                ),
                label: Text(
                  hasError ? l10n.sessionRetryButton : l10n.sessionStartButton,
                ),
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
