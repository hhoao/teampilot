import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:flutter_alacritty/input/paste.dart' as alacritty_paste;
import 'package:flutter_alacritty/input/term_mode.dart' show anyMouse;
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubits/layout_cubit.dart';
import '../l10n/l10n_extensions.dart';
import '../models/workspace_folder.dart';
import '../models/workspace_terminal_session_spec.dart';
import '../services/terminal/terminal_layout_coordinator.dart';
import '../services/terminal/terminal_theme_mapper.dart';
import '../services/terminal/terminal_uri_opener.dart';
import '../services/host/host_interactive_shell.dart';
import '../services/terminal/workspace_shell_connector.dart';
import '../services/terminal/workspace_terminal_connect_coordinator.dart';
import '../services/terminal/workspace_terminal_registry.dart';
import '../services/workspace/workspace_tools_scope.dart';
import '../theme/workspace_surface_layers.dart';
import '../utils/app_keys.dart';
import 'menu/sidebar_action_menu.dart';
import 'workspace_terminal/workspace_terminal_tab_bar.dart';
import 'workspace_terminal/workspace_terminal_view.dart';

/// Debug label for the workspace panel's stable [GlobalKey<TerminalViewState>].
const String kWorkspaceTerminalViewDebugLabel = 'workspace-terminal-view';

/// IntelliJ-style bottom panel: tab row + shell PTY (not chat agent terminals).
class WorkspaceTerminalPanel extends StatefulWidget {
  const WorkspaceTerminalPanel({
    required this.workspaceId,
    required this.workingDirectory,
    super.key,
  });

  final String workspaceId;
  final String workingDirectory;

  @override
  State<WorkspaceTerminalPanel> createState() => _WorkspaceTerminalPanelState();
}

class _WorkspaceTerminalPanelState extends State<WorkspaceTerminalPanel> {
  WorkspaceTerminalRegistry get _registry =>
      context.read<WorkspaceTerminalRegistry>();
  WorkspaceShellConnector get _connector =>
      context.read<WorkspaceShellConnector>();
  WorkspaceTerminalGroup get _group => _registry.groupFor(widget.workspaceId);

  WorkspaceTerminalConnectCoordinator? _connectCoordinator;

  var _bootstrapped = false;

  final _terminalViewKey = GlobalKey<TerminalViewState>(
    debugLabel: kWorkspaceTerminalViewDebugLabel,
  );

  TerminalLayoutCoordinator? _coordinator;
  PtyResizeHoldTarget? _registeredHoldTarget;
  TerminalViewState? _registeredViewState;
  var _registrationScheduled = false;

  List<WorkspaceFolder> get _folders =>
      WorkspaceToolsScope.maybeOf(context)?.effectiveFolders ?? const [];

  WorkspaceTerminalConnectCoordinator get _connect =>
      _connectCoordinator ??= WorkspaceTerminalConnectCoordinator(
        connector: _connector,
      );

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
        oldWidget.workspaceId != widget.workspaceId) {
      _syncActiveEntryCwd();
    }
  }

  @override
  void dispose() {
    if (_registeredHoldTarget != null) {
      _coordinator?.unregister(_registeredHoldTarget!);
    }
    _coordinator?.dispose();
    super.dispose();
  }

  WorkspaceTerminalEntry? get _activeEntry => _group.activeEntry;

  WorkspaceTerminalSessionSpec _defaultSpec(String cwd) =>
      defaultSessionSpecFor(
        cwd: cwd,
        folders: _folders,
        fallbackLocalShell: HostInteractiveShell.defaultExecutable(),
      );

  void _ensureDefaultEntry() {
    final cwd = widget.workingDirectory.trim();
    if (_group.entries.isNotEmpty) {
      for (final entry in _group.entries) {
        if (entry.connected && entry.controller.engine == null) {
          entry.controller.attach(entry.session.engine);
        }
      }
      if (mounted) setState(() {});
      return;
    }
    if (cwd.isEmpty) return;
    unawaited(
      _addEntry(
        cwd: cwd,
        spec: _defaultSpec(cwd),
        followWorkspace: true,
        select: true,
      ),
    );
  }

  void _syncActiveEntryCwd() {
    final cwd = widget.workingDirectory.trim();
    if (cwd.isEmpty) return;
    final active = _activeEntry;
    if (active == null) {
      unawaited(
        _addEntry(
          cwd: cwd,
          spec: _defaultSpec(cwd),
          followWorkspace: true,
          select: true,
        ),
      );
      return;
    }
    unawaited(_syncEntryWithWorkspace(active, cwd));
  }

  Future<void> _syncEntryWithWorkspace(
    WorkspaceTerminalEntry entry,
    String cwd,
  ) async {
    if (!entry.followWorkspace) {
      if (entry.cwd == cwd) return;
      entry.cwd = cwd;
      entry.connected = false;
      await _runConnect(entry);
      if (mounted) setState(() {});
      return;
    }

    final newSpec = _defaultSpec(cwd);
    final specChanged = newSpec != entry.spec;
    final cwdChanged = entry.cwd != cwd;
    if (!specChanged && !cwdChanged) return;

    entry.cwd = cwd;
    entry.bumpConnectGeneration();

    if (specChanged) {
      entry.session.dispose();
      entry.spec = newSpec;
      entry.session = _connector.createSession(newSpec);
      entry.titleLabel = await _connector.labelForSpec(newSpec);
      entry.controller.attach(entry.session.engine);
      entry.connected = false;
    } else {
      entry.connected = false;
    }

    await _runConnect(entry);
    if (mounted) setState(() {});
  }

  Future<void> _addEntry({
    required String cwd,
    required WorkspaceTerminalSessionSpec spec,
    required bool select,
    bool followWorkspace = false,
  }) async {
    final session = _connector.createSession(spec);
    final label = await _connector.labelForSpec(spec);
    final entry = _group.addEntry(
      cwd: cwd,
      spec: spec,
      session: session,
      select: select,
      titleLabel: label,
      followWorkspace: followWorkspace,
    );
    await _runConnect(entry);
    if (mounted) setState(() {});
  }

  Future<void> _runConnect(WorkspaceTerminalEntry entry) async {
    await _connect.connect(
      group: _group,
      entry: entry,
      theme: _terminalTheme(context),
      sshConnectFailedMessage: context.l10n.workspaceTerminalSshConnectFailed,
      onStateChanged: () {
        if (mounted) setState(() {});
      },
      mounted: () => mounted,
    );
  }

  void _selectEntry(String id) {
    _group.activeId = id;
    final entry = _group.entryById(id);
    if (entry != null &&
        !entry.connected &&
        entry.cwd.trim().isNotEmpty &&
        !entry.session.isDisposed) {
      unawaited(_runConnect(entry));
    }
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
      chrome: WorkspacePageChrome.workspace,
    );
  }

  void _syncTerminalViewRegistration() {
    final state = _terminalViewKey.currentState;
    if (identical(state, _registeredViewState)) return;
    if (_registeredHoldTarget != null) {
      _coordinator?.unregister(_registeredHoldTarget!);
      _registeredHoldTarget = null;
      _registeredViewState = null;
    }
    if (state == null) return;
    final target = ptyHoldTargetFor(state);
    _coordinator ??= TerminalLayoutCoordinator();
    _coordinator!.register(target);
    _registeredHoldTarget = target;
    _registeredViewState = state;
  }

  void _scheduleTerminalViewRegistration() {
    if (_registrationScheduled) return;
    _registrationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _registrationScheduled = false;
      if (mounted) _syncTerminalViewRegistration();
    });
  }

  void _refocusTerminal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _terminalViewKey.currentState?.requestTerminalFocus();
    });
  }

  Future<void> _showContextMenu(
    BuildContext menuContext,
    WorkspaceTerminalEntry entry,
    Offset globalPosition,
    CellOffset? cellOffset,
  ) async {
    final mloc = MaterialLocalizations.of(menuContext);
    final hasSelection = entry.controller.selectionActive;
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
    _refocusTerminal();
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

  void _closePanel() {
    _coordinator?.beginAllTransactions();
    context.read<LayoutCubit>().setWorkspaceTerminalVisible(false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _coordinator?.endAllTransactions(flush: true);
    });
  }

  void _onMenuSessionSelected(WorkspaceTerminalSessionSpec spec) {
    final dir = widget.workingDirectory.trim();
    if (dir.isEmpty) return;
    unawaited(_addEntry(cwd: dir, spec: spec, select: true));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cwd = widget.workingDirectory.trim();
    final active = _activeEntry;
    final theme = _terminalTheme(context);
    final terminalBackground = Color(0xFF000000 | theme.background);
    final terminalForeground = Color(0xFF000000 | theme.foreground);

    final terminalBody = active == null || cwd.isEmpty
        ? Center(
            child: Text(
              l10n.workspaceTerminalNoWorkingDirectory,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: terminalForeground.withValues(alpha: 0.65),
              ),
            ),
          )
        : WorkspaceTerminalView(
            entry: active,
            theme: theme,
            terminalViewKey: _terminalViewKey,
            siblings: _group.entries,
            onContextMenu: (position, cell) =>
                _showContextMenu(context, active, position, cell),
          );

    if (active != null && cwd.isNotEmpty) {
      _scheduleTerminalViewRegistration();
    }

    return ColoredBox(
      key: AppKeys.workspaceTerminalPanel,
      color: terminalBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WorkspaceTerminalTabBar(
            entries: _group.entries,
            activeEntryId: _group.activeId,
            onSelect: _selectEntry,
            onCloseEntry: _closeEntry,
            onQuickNew: () {
              final dir = widget.workingDirectory.trim();
              if (dir.isEmpty) return;
              unawaited(
                _addEntry(
                  cwd: dir,
                  spec: _defaultSpec(dir),
                  followWorkspace: true,
                  select: true,
                ),
              );
            },
            folders: _folders,
            connector: _connector,
            onSessionSelected: _onMenuSessionSelected,
            onClosePanel: _closePanel,
          ),
          Expanded(child: terminalBody),
        ],
      ),
    );
  }
}
