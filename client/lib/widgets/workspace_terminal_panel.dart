import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';
import 'package:flutter/services.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:flutter_alacritty/input/paste.dart' as alacritty_paste;
import 'package:flutter_alacritty/input/term_mode.dart' show anyMouse;
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubits/editor_cubit.dart';
import '../cubits/layout_cubit.dart';
import '../cubits/session_preferences_cubit.dart';
import '../l10n/l10n_extensions.dart';
import '../models/layout_preferences.dart';
import '../services/terminal/terminal_fonts.dart';
import '../services/terminal/terminal_theme_mapper.dart';
import '../theme/workspace_surface_layers.dart';
import '../services/terminal/terminal_uri_opener.dart';
import '../services/terminal/workspace_terminal_registry.dart';
import '../utils/app_keys.dart';
import 'app_icon_button.dart';
import 'menu/sidebar_action_menu.dart';
import 'resizable_split_view.dart';

/// Stable key for the workspace terminal's `TerminalView`. Shared across all
/// entries so switching tabs swaps the engine on a reused view (warm glyph
/// cache) instead of remounting and painting partial text. See
/// `chatWorkbenchTerminalViewKey` for the chat-workbench counterpart.
const Key kWorkspaceTerminalViewKey = ValueKey('workspace-terminal-view');

/// VS Code–style bottom panel: main terminal + session list (not chat agent PTY).
class WorkspaceTerminalPanel extends StatefulWidget {
  const WorkspaceTerminalPanel({
    required this.projectId,
    required this.workingDirectory,
    super.key,
  });

  final String projectId;
  final String workingDirectory;

  @override
  State<WorkspaceTerminalPanel> createState() => _WorkspaceTerminalPanelState();
}

class _WorkspaceTerminalPanelState extends State<WorkspaceTerminalPanel> {
  WorkspaceTerminalRegistry get _registry =>
      context.read<WorkspaceTerminalRegistry>();
  WorkspaceTerminalGroup get _group => _registry.groupFor(widget.projectId);

  var _bootstrapped = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_bootstrapped) return;
    _bootstrapped = true;
    _ensureDefaultEntry();
  }

  @override
  void didUpdateWidget(WorkspaceTerminalPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workingDirectory != widget.workingDirectory ||
        oldWidget.projectId != widget.projectId) {
      _syncActiveEntryCwd();
    }
  }

  // NOTE: no dispose() of sessions here — the registry owns their lifetime and
  // tears them down via disposeProject when the project tab is closed.

  WorkspaceTerminalEntry? get _activeEntry => _group.activeEntry;

  void _ensureDefaultEntry() {
    final cwd = widget.workingDirectory.trim();
    if (_group.entries.isNotEmpty) {
      // Revisiting a project: re-attach controllers to live sessions.
      for (final entry in _group.entries) {
        if (entry.connected && entry.controller.engine == null) {
          entry.controller.attach(entry.session.engine);
        }
      }
      if (mounted) setState(() {});
      return;
    }
    if (cwd.isEmpty) return;
    _addEntry(cwd, select: true);
  }

  void _syncActiveEntryCwd() {
    final cwd = widget.workingDirectory.trim();
    if (cwd.isEmpty) return;
    final active = _activeEntry;
    if (active == null) {
      _addEntry(cwd, select: true);
      return;
    }
    if (active.cwd == cwd) return;
    active.cwd = cwd;
    active.connected = false;
    _connectEntry(active);
    setState(() {});
  }

  void _addEntry(String cwd, {required bool select}) {
    final entry = _group.addEntry(cwd: cwd, select: select);
    _connectEntry(entry);
    setState(() {});
  }

  void _closeEntry(String id) {
    final nowEmpty = _group.removeEntry(id);
    if (nowEmpty) {
      if (mounted) {
        context.read<LayoutCubit>().setWorkspaceTerminalVisible(false);
      }
      return;
    }
    setState(() {});
  }

  TerminalTheme _terminalTheme(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mode = context
        .read<LayoutCubit>()
        .state
        .preferences
        .terminalThemeMode;
    return teampilotTerminalTheme(
      cs,
      isDark: isDark,
      mode: mode,
      chrome: WorkspacePageChrome.project,
    );
  }

  void _connectEntry(WorkspaceTerminalEntry entry) {
    final cwd = entry.cwd.trim();
    if (cwd.isEmpty) return;
    if (entry.connected && entry.session.isRunning) return;

    final theme = _terminalTheme(context);
    entry.session.applyTerminalTheme(theme);
    entry.connected = true;
    entry.session.connectShell(
      workingDirectory: cwd,
      onProcessStarted: () {
        if (mounted) setState(() {});
      },
      onProcessFailed: (_) {
        if (mounted) setState(() {});
      },
      onProcessExited: () {
        entry.connected = false;
        if (mounted) setState(() {});
      },
    );
    if (entry.controller.engine == null) {
      entry.controller.attach(entry.session.engine);
    }
  }

  Future<void> _showContextMenu(
    BuildContext menuContext,
    WorkspaceTerminalEntry entry,
    Offset globalPosition,
    CellOffset? cellOffset,
  ) async {
    final mloc = MaterialLocalizations.of(menuContext);
    final hasSelection = entry.controller.selectionActive;
    // Mouse reporting (TUI) eats plain left-drag, so a terminal selection never
    // forms and Copy stays disabled. Hint the standard Shift+drag escape hatch.
    final mouseReporting = anyMouse(entry.session.engine.grid.modeFlags);
    final linkUri = cellOffset != null
        ? entry.session.engine.hyperlinkAt(cellOffset.row, cellOffset.column)
        : null;
    final specs = <SidebarActionMenuSpec>[
      if (linkUri != null)
        SidebarActionMenuSpec.item(
          value: 'openLink',
          icon: Icons.link,
          label: context.l10n.terminalOpenLink,
        ),
      if (linkUri != null) const SidebarActionMenuSpec.divider(),
      SidebarActionMenuSpec.item(
        value: 'paste',
        icon: Icons.content_paste,
        label: mloc.pasteButtonLabel,
      ),
      SidebarActionMenuSpec.item(
        value: 'copy',
        icon: Icons.content_copy,
        label: (!hasSelection && mouseReporting)
            ? menuContext.l10n.terminalCopySelectHint
            : mloc.copyButtonLabel,
        enabled: hasSelection,
      ),
      SidebarActionMenuSpec.item(
        value: 'selectAll',
        icon: Icons.select_all,
        label: mloc.selectAllButtonLabel,
      ),
    ];

    final selected = await showSidebarActionMenuFromSpecs<String>(
      context: menuContext,
      globalPosition: globalPosition,
      popUpAnimationStyle: const AnimationStyle(duration: Duration.zero),
      specs: specs,
    );
    if (!menuContext.mounted) return;
    switch (selected) {
      case 'openLink':
        if (linkUri != null) {
          await TerminalUriOpener.open(linkUri, workingDirectory: entry.cwd);
        }
      case 'paste':
        final data = await Clipboard.getData(Clipboard.kTextPlain);
        final text = data?.text;
        if (text != null && text.isNotEmpty) {
          entry.controller.onTerminalInputStart();
          entry.session.engine.write(
            alacritty_paste.pasteBytes(
              text,
              modeFlags: entry.session.engine.grid.modeFlags,
            ),
          );
          entry.controller.clearSelection();
        }
      case 'copy':
        final text = entry.controller.readSelectionText();
        if (text != null && text.isNotEmpty) {
          await Clipboard.setData(ClipboardData(text: text));
        }
      case 'selectAll':
        final grid = entry.session.engine.grid;
        if (grid.rows > 0 && grid.columns > 0) {
          entry.controller.selectionStart(0, 0, false, 0);
          entry.controller.selectionUpdate(
            grid.rows - 1,
            grid.columns - 1,
            false,
          );
        }
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cwd = widget.workingDirectory.trim();
    final active = _activeEntry;
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
            entry: active,
            theme: theme,
            onContextMenu: (position, cell) =>
                _showContextMenu(context, active, position, cell),
          );

    return ColoredBox(
      key: AppKeys.workspaceTerminalPanel,
      color: terminalBackground,
      child: ResizableSplitView(
        axis: Axis.horizontal,
        primaryAtEnd: true,
        first: terminalBody,
        second: _WorkspaceTerminalSessionSidebar(
          theme: theme,
          entries: _group.entries,
          activeEntryId: _group.activeId,
          onSelect: (id) => setState(() => _group.activeId = id),
          onCloseEntry: _closeEntry,
          onNewTab: () {
            final dir = widget.workingDirectory.trim();
            if (dir.isEmpty) return;
            _addEntry(dir, select: true);
          },
          onClosePanel: () =>
              context.read<LayoutCubit>().setWorkspaceTerminalVisible(false),
        ),
        initialPrimarySize: sessionSidebarWidth,
        minPrimarySize:
            LayoutPreferences.minWorkspaceTerminalSessionSidebarWidth,
        minSecondarySize: LayoutPreferences.minWorkspaceTerminalMainWidth,
        maxPrimarySize:
            LayoutPreferences.maxWorkspaceTerminalSessionSidebarWidth,
        onPrimarySizeChanged: (width) {
          context.read<LayoutCubit>().setWorkspaceTerminalSessionSidebarWidth(
            width,
          );
        },
      ),
    );
  }
}

class _WorkspaceTerminalView extends StatelessWidget {
  const _WorkspaceTerminalView({
    required this.entry,
    required this.theme,
    required this.onContextMenu,
  });

  final WorkspaceTerminalEntry entry;
  final TerminalTheme theme;
  final void Function(Offset globalPosition, CellOffset? cell) onContextMenu;

  @override
  Widget build(BuildContext context) {
    final background = Color(0xFF000000 | theme.background);
    return ColoredBox(
      color: background,
      child: TerminalView(
        entry.session.engine,
        key: kWorkspaceTerminalViewKey,
        controller: entry.controller,
        theme: theme,
        backgroundOpacity: 0.98,
        padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 8),
        textStyle: appTerminalTextStyle(context),
        autofocus: true,
        linkProviders: entry.session.linkProviders,
        primaryTapActivatesLink: context
            .watch<SessionPreferencesCubit>()
            .state
            .preferences
            .terminalLinkClickOpensInApp,
        onViewportResize: entry.session.onViewportResize,
        onLinkActivate: (uri) {
          final editorCubit = context.read<EditorCubit>();
          unawaited(
            TerminalUriOpener.open(
              uri,
              workingDirectory: entry.cwd,
              openInEditor: (path) => editorCubit.openFile(path),
            ),
          );
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
    required this.entries,
    required this.activeEntryId,
    required this.onSelect,
    required this.onCloseEntry,
    required this.onNewTab,
    required this.onClosePanel,
  });

  final TerminalTheme theme;
  final List<WorkspaceTerminalEntry> entries;
  final String? activeEntryId;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onCloseEntry;
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
                  AppIconButton(
                    icon: Icons.add,
                    color: muted,
                    size: AppIconButton.kCompactSize,
                    tooltip: l10n.workspaceTerminalNewSession,
                    onTap: onNewTab,
                  ),
                  AppIconButton(
                    icon: Icons.close,
                    color: muted,
                    size: AppIconButton.kCompactSize,
                    tooltip: l10n.workspaceTerminalClose,
                    onTap: onClosePanel,
                  ),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: divider),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final entry = entries[index];
                final selected = entry.id == activeEntryId;
                final itemColor = selected ? foreground : muted;
                final itemTextStyle = Theme.of(context).textTheme.bodySmall
                        ?.copyWith(
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w500,
                          color: itemColor,
                        ) ??
                    const TextStyle();
                return TweenAnimationBuilder<Color?>(
                  tween: ColorTween(
                    begin: selected
                        ? Colors.transparent
                        : selectedFill,
                    end: selected ? selectedFill : Colors.transparent,
                  ),
                  duration: 200.ms,
                  curve: Curves.easeOutCubic,
                  builder: (context, color, child) {
                    return Material(
                      color: color,
                      child: child,
                    );
                  },
                  child: InkWell(
                    onTap: () => onSelect(entry.id),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.terminal,
                            size: context.appIconSizes.md,
                            color: itemColor,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: AnimatedDefaultTextStyle(
                              duration: 200.ms,
                              curve: Curves.easeOutCubic,
                              style: itemTextStyle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              child: Text(entry.title()),
                            ),
                          ),
                          AppIconButton(
                            icon: Icons.close,
                            iconSize: context.appIconSizes.md,
                            color: itemColor,
                            size: AppIconButton.kCompactSize,
                            tooltip: l10n.workspaceTerminalCloseSession,
                            onTap: () => onCloseEntry(entry.id),
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
