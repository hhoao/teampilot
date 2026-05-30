import 'dart:async';
import 'dart:math' show min;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:flutter_alacritty/input/paste.dart' as alacritty_paste;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../cubits/layout_cubit.dart';
import '../l10n/l10n_extensions.dart';
import '../models/layout_preferences.dart';
import '../services/terminal/terminal_fonts.dart';
import '../services/terminal/terminal_session.dart';
import '../services/terminal/terminal_theme_mapper.dart';
import '../services/terminal/terminal_uri_opener.dart';
import '../services/terminal/workspace_interactive_shell.dart';
import '../utils/app_keys.dart';
import '../utils/context_menu_position.dart';
import 'split_layout.dart';

const _uuid = Uuid();

/// VS Code–style bottom panel: main terminal + session list (not chat agent PTY).
class WorkspaceTerminalPanel extends StatefulWidget {
  const WorkspaceTerminalPanel({
    required this.workingDirectory,
    super.key,
  });

  final String workingDirectory;

  @override
  State<WorkspaceTerminalPanel> createState() => _WorkspaceTerminalPanelState();
}

class _WorkspaceTerminalTab {
  _WorkspaceTerminalTab({required this.id, required this.cwd})
    : session = TerminalSession(
        executable: WorkspaceInteractiveShell.executable(),
        validateLaunch: false,
        parseExecutable: false,
      ),
      controller = TerminalController();

  final String id;
  String cwd;
  bool connected = false;
  final TerminalSession session;
  final TerminalController controller;

  String title() {
    final shell = p.basename(WorkspaceInteractiveShell.executable());
    if (cwd.isEmpty) return shell;
    return '$shell ${p.basename(cwd)}';
  }

  void dispose() {
    session.disconnect();
    controller.dispose();
  }
}

class _WorkspaceTerminalPanelState extends State<WorkspaceTerminalPanel> {
  final List<_WorkspaceTerminalTab> _tabs = [];
  String? _activeTabId;
  var _bootstrapped = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_bootstrapped) return;
    _bootstrapped = true;
    _ensureDefaultTab();
  }

  @override
  void didUpdateWidget(WorkspaceTerminalPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workingDirectory != widget.workingDirectory) {
      _syncActiveTabCwd();
    }
  }

  @override
  void dispose() {
    for (final tab in _tabs) {
      tab.dispose();
    }
    super.dispose();
  }

  _WorkspaceTerminalTab? get _activeTab {
    if (_activeTabId == null) return null;
    for (final tab in _tabs) {
      if (tab.id == _activeTabId) return tab;
    }
    return null;
  }

  void _ensureDefaultTab() {
    final cwd = widget.workingDirectory.trim();
    if (_tabs.isNotEmpty) return;
    if (cwd.isEmpty) return;
    _addTab(cwd, select: true);
  }

  void _syncActiveTabCwd() {
    final cwd = widget.workingDirectory.trim();
    if (cwd.isEmpty) return;
    final active = _activeTab;
    if (active == null) {
      _addTab(cwd, select: true);
      return;
    }
    if (active.cwd == cwd) return;
    active.cwd = cwd;
    active.connected = false;
    _connectTab(active);
    setState(() {});
  }

  void _addTab(String cwd, {required bool select}) {
    final tab = _WorkspaceTerminalTab(id: _uuid.v4(), cwd: cwd);
    _tabs.add(tab);
    if (select) {
      _activeTabId = tab.id;
    }
    _connectTab(tab);
    setState(() {});
  }

  void _closeTab(String id) {
    final index = _tabs.indexWhere((t) => t.id == id);
    if (index < 0) return;
    final closing = _tabs[index];
    final wasActive = closing.id == _activeTabId;
    closing.dispose();
    _tabs.removeAt(index);
    if (_tabs.isEmpty) {
      _activeTabId = null;
      context.read<LayoutCubit>().setWorkspaceTerminalVisible(false);
      return;
    }
    if (wasActive) {
      _activeTabId = _tabs[min(index, _tabs.length - 1)].id;
    }
    setState(() {});
  }

  TerminalTheme _terminalTheme(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mode = context.read<LayoutCubit>().state.preferences.terminalThemeMode;
    return teampilotTerminalTheme(cs, isDark: isDark, mode: mode);
  }

  void _connectTab(_WorkspaceTerminalTab tab) {
    final cwd = tab.cwd.trim();
    if (cwd.isEmpty) return;
    if (tab.connected && tab.session.isRunning) return;

    final theme = _terminalTheme(context);
    tab.session.applyTerminalTheme(theme);
    tab.connected = true;
    tab.session.connectShell(
      workingDirectory: cwd,
      onProcessStarted: () {
        if (mounted) setState(() {});
      },
      onProcessFailed: (_) {
        if (mounted) setState(() {});
      },
      onProcessExited: () {
        tab.connected = false;
        if (mounted) setState(() {});
      },
    );
    if (tab.controller.engine == null) {
      tab.controller.attach(tab.session.engine);
    }
  }

  Future<void> _showContextMenu(
    BuildContext menuContext,
    _WorkspaceTerminalTab tab,
    Offset globalPosition,
    CellOffset? cellOffset,
  ) async {
    final mloc = MaterialLocalizations.of(menuContext);
    final hasSelection = tab.controller.selectionActive;
    final linkUri = cellOffset != null
        ? tab.session.engine.hyperlinkAt(cellOffset.row, cellOffset.column)
        : null;
    final entries = <PopupMenuEntry<String>>[
      if (linkUri != null)
        PopupMenuItem(
          value: 'openLink',
          child: Text(context.l10n.terminalOpenLink),
        ),
      const PopupMenuDivider(),
      PopupMenuItem(value: 'paste', child: Text(mloc.pasteButtonLabel)),
      PopupMenuItem(
        value: 'copy',
        enabled: hasSelection,
        child: Text(mloc.copyButtonLabel),
      ),
      PopupMenuItem(value: 'selectAll', child: Text(mloc.selectAllButtonLabel)),
    ];

    final selected = await showMenu<String>(
      context: menuContext,
      position: contextMenuPositionForGlobal(menuContext, globalPosition),
      useRootNavigator: true,
      popUpAnimationStyle: const AnimationStyle(duration: Duration.zero),
      items: entries,
    );
    if (!menuContext.mounted) return;
    switch (selected) {
      case 'openLink':
        if (linkUri != null) {
          await TerminalUriOpener.open(linkUri, workingDirectory: tab.cwd);
        }
      case 'paste':
        final data = await Clipboard.getData(Clipboard.kTextPlain);
        final text = data?.text;
        if (text != null && text.isNotEmpty) {
          tab.controller.onTerminalInputStart();
          tab.session.engine.write(
            alacritty_paste.pasteBytes(
              text,
              modeFlags: tab.session.engine.grid.modeFlags,
            ),
          );
          tab.controller.clearSelection();
        }
      case 'copy':
        final text = tab.controller.readSelectionText();
        if (text != null && text.isNotEmpty) {
          await Clipboard.setData(ClipboardData(text: text));
        }
      case 'selectAll':
        final grid = tab.session.engine.grid;
        if (grid.rows > 0 && grid.columns > 0) {
          tab.controller.selectionStart(0, 0, false, 0);
          tab.controller.selectionUpdate(grid.rows - 1, grid.columns - 1, false);
        }
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cwd = widget.workingDirectory.trim();
    final active = _activeTab;
    final theme = _terminalTheme(context);
    final terminalBackground = Color(0xFF000000 | theme.background);
    final terminalForeground = Color(0xFF000000 | theme.foreground);
    final sessionSidebarWidth = context
        .select<LayoutCubit, double>(
          (c) => c.state.preferences.workspaceTerminalSessionSidebarWidth,
        )
        .clamp(
          LayoutPreferences.minWorkspaceTerminalSessionSidebarWidth,
          LayoutPreferences.maxWorkspaceTerminalSessionSidebarWidth,
        );

  final terminalBody = active == null || cwd.isEmpty
      ? Center(
          child: Text(
            l10n.workspaceTerminalNoWorkingDirectory,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: terminalForeground.withValues(alpha: 0.65),
            ),
          ),
        )
      : _WorkspaceTerminalView(
          tab: active,
          theme: theme,
          onContextMenu: (position, cell) => _showContextMenu(
            context,
            active,
            position,
            cell,
          ),
        );

    return ColoredBox(
      key: AppKeys.workspaceTerminalPanel,
      color: terminalBackground,
      child: ResizableTrailingPaneView(
        leading: terminalBody,
        trailing: _WorkspaceTerminalSessionSidebar(
          theme: theme,
          tabs: _tabs,
          activeTabId: _activeTabId,
          onSelect: (id) => setState(() => _activeTabId = id),
          onCloseTab: _closeTab,
          onNewTab: () {
            final dir = widget.workingDirectory.trim();
            if (dir.isEmpty) return;
            _addTab(dir, select: true);
          },
          onClosePanel: () =>
              context.read<LayoutCubit>().setWorkspaceTerminalVisible(false),
        ),
        trailingWidth: sessionSidebarWidth,
        minTrailingWidth:
            LayoutPreferences.minWorkspaceTerminalSessionSidebarWidth,
        maxTrailingWidth:
            LayoutPreferences.maxWorkspaceTerminalSessionSidebarWidth,
        onTrailingWidthChanged: (width) {
          context
              .read<LayoutCubit>()
              .setWorkspaceTerminalSessionSidebarWidth(width);
        },
      ),
    );
  }
}

class _WorkspaceTerminalView extends StatelessWidget {
  const _WorkspaceTerminalView({
    required this.tab,
    required this.theme,
    required this.onContextMenu,
  });

  final _WorkspaceTerminalTab tab;
  final TerminalTheme theme;
  final void Function(Offset globalPosition, CellOffset? cell) onContextMenu;

  @override
  Widget build(BuildContext context) {
    final background = Color(0xFF000000 | theme.background);
    return ColoredBox(
      color: background,
      child: TerminalView(
        tab.session.engine,
        key: ValueKey(tab.id),
        controller: tab.controller,
        theme: theme,
        backgroundOpacity: 0.98,
        padding: const EdgeInsets.all(8),
        textStyle: appTerminalTextStyle(context),
        autofocus: true,
        onViewportResize: tab.session.onViewportResize,
        onLinkActivate: (uri) {
          unawaited(TerminalUriOpener.open(uri, workingDirectory: tab.cwd));
        },
        onSecondaryTapDown: (details, offset) {
          onContextMenu(details.globalPosition, offset);
        },
      ),
    );
  }
}

class _WorkspaceTerminalSessionSidebar extends StatelessWidget {
  const _WorkspaceTerminalSessionSidebar({
    required this.theme,
    required this.tabs,
    required this.activeTabId,
    required this.onSelect,
    required this.onCloseTab,
    required this.onNewTab,
    required this.onClosePanel,
  });

  final TerminalTheme theme;
  final List<_WorkspaceTerminalTab> tabs;
  final String? activeTabId;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onCloseTab;
  final VoidCallback onNewTab;
  final VoidCallback onClosePanel;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final background = Color(0xFF000000 | theme.background);
    final foreground = Color(0xFF000000 | theme.foreground);
    final muted = foreground.withValues(alpha: 0.65);
    final divider = foreground.withValues(alpha: 0.18);
    final selectedFill = foreground.withValues(alpha: 0.12);

    return ColoredBox(
      color: background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 32,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      l10n.workspaceTerminal,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: muted,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.workspaceTerminalNewSession,
                    icon: Icon(Icons.add, size: 18, color: muted),
                    onPressed: onNewTab,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.workspaceTerminalClose,
                    icon: Icon(Icons.close, size: 18, color: muted),
                    onPressed: onClosePanel,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: divider),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: tabs.length,
              itemBuilder: (context, index) {
                final tab = tabs[index];
                final selected = tab.id == activeTabId;
                final itemColor = selected ? foreground : muted;
                return Material(
                  color: selected ? selectedFill : Colors.transparent,
                  child: InkWell(
                    onTap: () => onSelect(tab.id),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.terminal, size: 16, color: itemColor),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              tab.title(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    fontWeight: selected
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                    color: itemColor,
                                  ),
                            ),
                          ),
                          SizedBox(
                            width: 28,
                            height: 28,
                            child: IconButton(
                              tooltip: l10n.workspaceTerminalCloseSession,
                              padding: EdgeInsets.zero,
                              icon: Icon(Icons.close, size: 14, color: itemColor),
                              onPressed: () => onCloseTab(tab.id),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
