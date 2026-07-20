import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubits/layout_cubit.dart';
import '../cubits/run_cubit.dart';
import '../l10n/l10n_extensions.dart';
import '../models/run/run_session.dart';
import '../models/run/run_ui_intent.dart';
import '../models/workspace_folder.dart';
import '../models/workspace_terminal_session_spec.dart';
import '../pages/workspace_shell/workspace_shell_tabs.dart';
import '../services/run/launch_type_normalize.dart';
import '../services/terminal/terminal_theme_mapper.dart';
import '../services/terminal/workspace_shell_connector.dart';
import '../services/terminal/workspace_terminal_connect_coordinator.dart';
import '../services/terminal/workspace_terminal_registry.dart';
import '../services/terminal/workspace_terminal_run_service.dart';
import '../services/terminal/workspace_terminal_session_ops.dart';
import '../services/terminal/workspace_terminal_title_resolver.dart';
import '../services/workspace/workspace_tools_scope.dart';
import '../theme/workspace_surface_layers.dart';
import 'run/run_panel.dart';
import 'run/run_session_dismiss.dart';
import 'workspace_dock_tab.dart';
import 'workspace_terminal/workspace_terminal_new_session_menu.dart';
import 'workspace_terminal_panel.dart';
import 'package:shared_ui/shared_ui.dart';

/// Which bottom tool is visible in the workspace IDE shell.
enum WorkspaceBottomDockTab { terminal, run }

/// Dock tab to select for [intent], or null when [RunUiIntent.activateToolWindow]
/// is false (do not switch tab / reveal dock).
///
/// Prefer `resolveWorkbenchTabForRunIntent` in `workbench_run_intent.dart` for
/// center workbench shell/run tabs; this helper remains until the dock is removed.
WorkspaceBottomDockTab? dockTabForActivateIntent(RunUiIntent intent) {
  if (!intent.activateToolWindow) return null;
  return intent.surface == RunToolSurface.terminal
      ? WorkspaceBottomDockTab.terminal
      : WorkspaceBottomDockTab.run;
}

/// Bottom chrome: unified session chips (shell + Run) and a single `+` launcher.
///
/// Orca-style: no Terminal|Run segmented control. `+` opens the shell launch
/// catalog only; starting a Run configuration adds a Run instance tab.
class WorkspaceBottomDock extends StatefulWidget {
  const WorkspaceBottomDock({
    required this.workspaceId,
    required this.workingDirectory,
    this.holdHandle,
    this.terminalKey,
    this.initialTab = WorkspaceBottomDockTab.terminal,
    super.key,
  });

  final String workspaceId;
  final String workingDirectory;
  final WorkspaceTerminalHoldHandle? holdHandle;
  final Key? terminalKey;
  final WorkspaceBottomDockTab initialTab;

  @override
  State<WorkspaceBottomDock> createState() => _WorkspaceBottomDockState();
}

class _WorkspaceBottomDockState extends State<WorkspaceBottomDock> {
  final _plusKey = GlobalKey();
  final _sessionOps = WorkspaceTerminalSessionOps();

  WorkspaceDockTab? _active;
  Set<String> _seenSessionIds = {};
  StreamSubscription<RunUiIntent>? _uiIntentSub;
  RunCubit? _subscribedCubit;

  WorkspaceTerminalRegistry get _registry =>
      context.read<WorkspaceTerminalRegistry>();
  WorkspaceShellConnector get _connector =>
      context.read<WorkspaceShellConnector>();
  WorkspaceTerminalGroup get _group => _registry.groupFor(widget.workspaceId);

  List<WorkspaceFolder> get _folders =>
      WorkspaceToolsScope.maybeOf(context)?.effectiveFolders ?? const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final cubit = context.read<RunCubit>();
    if (identical(_subscribedCubit, cubit)) return;
    unawaited(_uiIntentSub?.cancel());
    _subscribedCubit = cubit;
    _uiIntentSub = cubit.uiIntents.listen(_onUiIntent);
  }

  @override
  void dispose() {
    unawaited(_uiIntentSub?.cancel());
    _uiIntentSub = null;
    _subscribedCubit = null;
    super.dispose();
  }

  void _onUiIntent(RunUiIntent intent) {
    if (!mounted) return;

    final nextTab = dockTabForActivateIntent(intent);
    if (nextTab != null) {
      final layout = context.read<LayoutCubit>();
      if (!layout.state.preferences.workspaceTerminalVisible) {
        unawaited(layout.setWorkspaceTerminalVisible(true));
      }
    }

    final entryId = intent.terminalEntryId?.trim();
    if (entryId != null &&
        entryId.isNotEmpty &&
        intent.surface == RunToolSurface.terminal) {
      widget.holdHandle?.selectEntry(entryId);
      setState(() => _active = WorkspaceDockShellTab(entryId));
    } else if (nextTab == WorkspaceBottomDockTab.run) {
      final sessions = context.read<RunCubit>().state.sessions;
      if (sessions.isNotEmpty) {
        setState(() => _active = WorkspaceDockRunTab(sessions.last.id));
      }
    }

    if (intent.focusToolWindow &&
        intent.surface == RunToolSurface.terminal) {
      widget.holdHandle?.requestFocus();
    }
  }

  void _onSessionsChanged(RunState state) {
    final ids = state.sessions.map((s) => s.id).toSet();
    final added = ids.difference(_seenSessionIds);
    _seenSessionIds = ids;
    if (added.isEmpty) return;

    final shouldRevealRun = state.sessions.any(
      (session) =>
          added.contains(session.id) && _sessionUsesRunPanel(session),
    );
    if (!shouldRevealRun) return;

    final layout = context.read<LayoutCubit>();
    if (!layout.state.preferences.workspaceTerminalVisible) {
      unawaited(layout.setWorkspaceTerminalVisible(true));
    }
    setState(() => _active = WorkspaceDockRunTab(added.last));
  }

  void _selectShell(String entryId) {
    widget.holdHandle?.selectEntry(entryId);
    setState(() => _active = WorkspaceDockShellTab(entryId));
  }

  void _selectRun(String sessionId) {
    setState(() => _active = WorkspaceDockRunTab(sessionId));
  }

  Future<void> _closeShell(String entryId) async {
    context.read<WorkspaceTerminalRunService>().handleEntryClosed(entryId);
    _group.removeEntry(entryId);
    _syncActiveAfterClose();
    _maybeHideWhenEmpty();
  }

  Future<void> _closeRun(RunSession session) async {
    final dismissed = await dismissRunSessionWithConfirm(
      context: context,
      cubit: context.read<RunCubit>(),
      session: session,
    );
    if (!dismissed || !mounted) return;
    _syncActiveAfterClose();
    _maybeHideWhenEmpty();
  }

  void _syncActiveAfterClose() {
    final active = _active;
    if (active is WorkspaceDockShellTab &&
        _group.entryById(active.entryId) == null) {
      final nextShell = _group.activeId;
      if (nextShell != null) {
        _active = WorkspaceDockShellTab(nextShell);
      } else {
        final runs = context.read<RunCubit>().state.sessions;
        _active = runs.isEmpty ? null : WorkspaceDockRunTab(runs.last.id);
      }
    } else if (active is WorkspaceDockRunTab) {
      final runs = context.read<RunCubit>().state.sessions;
      if (!runs.any((s) => s.id == active.sessionId)) {
        if (runs.isNotEmpty) {
          _active = WorkspaceDockRunTab(runs.last.id);
        } else {
          final nextShell = _group.activeId;
          _active = nextShell == null
              ? null
              : WorkspaceDockShellTab(nextShell);
        }
      }
    }
    if (mounted) setState(() {});
  }

  void _maybeHideWhenEmpty() {
    final hasShell = _group.entries.isNotEmpty;
    final hasRun = context.read<RunCubit>().state.sessions.isNotEmpty;
    if (!hasShell && !hasRun && mounted) {
      unawaited(
        context.read<LayoutCubit>().setWorkspaceTerminalVisible(false),
      );
    }
  }

  Future<void> _openShellSpec(WorkspaceTerminalSessionSpec spec) async {
    final cwd = widget.workingDirectory.trim();
    if (cwd.isEmpty || !mounted) return;
    final entry = await _sessionOps.openEntry(
      group: _group,
      connector: _connector,
      connectCoordinator: WorkspaceTerminalConnectCoordinator(
        connector: _connector,
      ),
      cwd: cwd,
      spec: spec,
      theme: _shellTheme(context),
      sshConnectFailedMessage: context.l10n.workspaceTerminalSshConnectFailed,
      select: true,
      followWorkspace: true,
      onStateChanged: () {
        if (mounted) setState(() {});
      },
      mounted: () => mounted,
    );
    if (!mounted) return;
    setState(() => _active = WorkspaceDockShellTab(entry.id));
  }

  Future<void> _showPlusMenu() async {
    final box = _plusKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final anchor = box.localToGlobal(box.size.bottomLeft(Offset.zero));
    await showWorkspaceTerminalLaunchMenu(
      context: context,
      globalPosition: anchor + const Offset(0, 4),
      folders: _folders,
      connector: _connector,
      onSessionSelected: (spec) => unawaited(_openShellSpec(spec)),
    );
  }

  TerminalTheme _shellTheme(BuildContext context) {
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final muted = cs.onSurfaceVariant;

    return BlocListener<RunCubit, RunState>(
      listenWhen: (prev, next) => prev.sessions != next.sessions,
      listener: (context, state) => _onSessionsChanged(state),
      child: ListenableBuilder(
        listenable: _group,
        builder: (context, _) {
          return BlocBuilder<RunCubit, RunState>(
            buildWhen: (a, b) => a.sessions != b.sessions,
            builder: (context, runState) {
              final shellEntries = _group.entries;
              final runSessions = runState.sessions;
              _ensureActiveSelection(shellEntries, runSessions);

              final showingRun = _active is WorkspaceDockRunTab;
              final activeRunId = switch (_active) {
                WorkspaceDockRunTab(:final sessionId) => sessionId,
                _ => null,
              };

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _DockHeader(
                    plusKey: _plusKey,
                    muted: muted,
                    shellEntries: shellEntries,
                    runSessions: runSessions,
                    active: _active,
                    onSelectShell: _selectShell,
                    onSelectRun: _selectRun,
                    onCloseShell: (id) => unawaited(_closeShell(id)),
                    onCloseRun: (session) => unawaited(_closeRun(session)),
                    onPlus: () => unawaited(_showPlusMenu()),
                    onHide: () => unawaited(
                      context.read<LayoutCubit>().setWorkspaceTerminalVisible(
                        false,
                      ),
                    ),
                    newSessionTooltip: l10n.workspaceTerminalNewSession,
                    hideTooltip: l10n.bottomDockPanelHidden,
                  ),
                  Expanded(
                    child: IndexedStack(
                      index: showingRun ? 1 : 0,
                      children: [
                        WorkspaceTerminalPanel(
                          key: widget.terminalKey,
                          workspaceId: widget.workspaceId,
                          workingDirectory: widget.workingDirectory,
                          holdHandle: widget.holdHandle,
                          showChrome: false,
                          activeEntryId: switch (_active) {
                            WorkspaceDockShellTab(:final entryId) => entryId,
                            _ => null,
                          },
                          onRequestNewTerminal: () =>
                              unawaited(_showPlusMenu()),
                        ),
                        RunPanel(
                          showChrome: false,
                          activeSessionId: activeRunId,
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  void _ensureActiveSelection(
    List<WorkspaceTerminalEntry> shellEntries,
    List<RunSession> runSessions,
  ) {
    final active = _active;
    if (active is WorkspaceDockShellTab) {
      if (shellEntries.any((e) => e.id == active.entryId)) return;
    } else if (active is WorkspaceDockRunTab) {
      if (runSessions.any((s) => s.id == active.sessionId)) return;
    }
    if (shellEntries.isNotEmpty) {
      final id = _group.activeId ?? shellEntries.last.id;
      _active = WorkspaceDockShellTab(id);
    } else if (runSessions.isNotEmpty) {
      _active = WorkspaceDockRunTab(runSessions.last.id);
    } else {
      _active = null;
    }
  }
}

bool _sessionUsesRunPanel(RunSession session) {
  return !isBuiltInShellType(session.owned.configuration.type);
}

class _DockHeader extends StatelessWidget {
  const _DockHeader({
    required this.plusKey,
    required this.muted,
    required this.shellEntries,
    required this.runSessions,
    required this.active,
    required this.onSelectShell,
    required this.onSelectRun,
    required this.onCloseShell,
    required this.onCloseRun,
    required this.onPlus,
    required this.onHide,
    required this.newSessionTooltip,
    required this.hideTooltip,
  });

  final GlobalKey plusKey;
  final Color muted;
  final List<WorkspaceTerminalEntry> shellEntries;
  final List<RunSession> runSessions;
  final WorkspaceDockTab? active;
  final ValueChanged<String> onSelectShell;
  final ValueChanged<String> onSelectRun;
  final ValueChanged<String> onCloseShell;
  final ValueChanged<RunSession> onCloseRun;
  final VoidCallback onPlus;
  final VoidCallback onHide;
  final String newSessionTooltip;
  final String hideTooltip;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final activeShellId = switch (active) {
      WorkspaceDockShellTab(:final entryId) => entryId,
      _ => null,
    };
    final activeRunId = switch (active) {
      WorkspaceDockRunTab(:final sessionId) => sessionId,
      _ => null,
    };

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final entry in shellEntries)
                    WorkspaceShellTabChip(
                      key: ValueKey(entry.id),
                      title: _shellTitle(entry),
                      active: entry.id == activeShellId,
                      onTap: () => onSelectShell(entry.id),
                      onClose: () => onCloseShell(entry.id),
                      accentColor: cs.primary,
                      icon: Icons.terminal_outlined,
                    ),
                  for (final session in runSessions)
                    WorkspaceShellTabChip(
                      key: ValueKey('run-${session.id}'),
                      title: session.owned.configuration.name,
                      active: session.id == activeRunId,
                      working:
                          session.status == RunSessionStatus.running ||
                          session.status == RunSessionStatus.starting,
                      onTap: () => onSelectRun(session.id),
                      onClose: () => onCloseRun(session),
                      accentColor: cs.primary,
                      icon: Icons.play_arrow_rounded,
                    ),
                  KeyedSubtree(
                    key: plusKey,
                    child: TpIconButton(
                      icon: Icons.add,
                      color: muted,
                      size: TpIconButton.kCompactSize,
                      tooltip: newSessionTooltip,
                      onTap: onPlus,
                    ),
                  ),
                ],
              ),
            ),
          ),
          TpIconButton(
            icon: Icons.remove,
            color: muted,
            size: TpIconButton.kCompactSize,
            tooltip: hideTooltip,
            onTap: onHide,
          ),
        ],
      ),
    );
  }

  String _shellTitle(WorkspaceTerminalEntry entry) {
    final baseLabel = entry.titleLabel.isEmpty ? '…' : entry.titleLabel;
    return WorkspaceTerminalTitleResolver.tabTitle(
      entry: entry,
      siblings: shellEntries,
      baseLabel: baseLabel,
    );
  }
}
