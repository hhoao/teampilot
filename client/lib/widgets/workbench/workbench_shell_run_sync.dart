import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/floating_workspace/floating_workspace_cubit.dart';
import '../../cubits/run_cubit.dart';
import '../../cubits/workbench/workbench_cubit.dart';
import '../../cubits/workbench/workbench_tab.dart';
import '../../models/floating_workspace_tab.dart';
import '../../models/run/run_session.dart';
import '../../models/run/run_ui_intent.dart';
import '../../services/floating_workspace/floating_surface_registry.dart';
import '../../services/run/run_panel_session.dart';
import '../../services/terminal/workspace_terminal_registry.dart';
import '../../services/workbench/workbench_chat_bridge.dart';
import '../../services/workbench/workbench_shell_run_sync_logic.dart';
import '../workspace_terminal_panel.dart';

/// Maps a bar floating [WorkbenchTabId] to the [FloatingTab] view model the
/// panel renders, resolving title / payload from the domain surface by id.
///
/// Mirror of how the center strip resolves session facts: the bar stores only
/// the id; display data is derived on demand. Unknown kinds (session) return
/// null — the floating panel never renders center tabs.
FloatingTab? resolveFloatingTabForId({
  required FloatingSurfaceRegistry registry,
  required String workspaceId,
  required WorkbenchTabId id,
}) {
  if (id.kind == WorkbenchTabKind.session) return null;
  final surface = registry[surfaceIdFor(id.kind)!];
  if (surface == null) return null;
  return surface.createTab(workspaceId: workspaceId, payload: id.id);
}

/// Reconciles RunPanel sessions with floating run tabs and strips stale center
/// run tabs. (Session tabs reach the bar via [WorkbenchChatBridge]; run tabs
/// still reconcile here because they are owned by the RunPanel, not chat.)
///
/// Workspace shell entries are **not** projected here — they open on the
/// floating terminal surface via [WorkbenchShellLauncher].
class WorkbenchShellRunSync extends StatefulWidget {
  const WorkbenchShellRunSync({
    required this.workspaceId,
    required this.tabScopeId,
    required this.child,
    this.holdHandle,
    super.key,
  });

  final String workspaceId;
  final String tabScopeId;
  final Widget child;
  final WorkspaceTerminalHoldHandle? holdHandle;

  @override
  State<WorkbenchShellRunSync> createState() => _WorkbenchShellRunSyncState();
}

class _WorkbenchShellRunSyncState extends State<WorkbenchShellRunSync> {
  StreamSubscription<RunUiIntent>? _uiIntentSub;
  RunCubit? _subscribedCubit;
  WorkspaceTerminalGroup? _group;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bindRunCubit();
    _bindRegistryGroup();
    _reconcile();
  }

  @override
  void didUpdateWidget(covariant WorkbenchShellRunSync oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspaceId != widget.workspaceId ||
        oldWidget.tabScopeId != widget.tabScopeId) {
      _bindRegistryGroup();
      _reconcile();
    }
  }

  @override
  void dispose() {
    unawaited(_uiIntentSub?.cancel());
    _uiIntentSub = null;
    _subscribedCubit = null;
    _group = null;
    super.dispose();
  }

  void _bindRunCubit() {
    final cubit = context.read<RunCubit>();
    if (identical(_subscribedCubit, cubit)) return;
    unawaited(_uiIntentSub?.cancel());
    _subscribedCubit = cubit;
    _uiIntentSub = cubit.uiIntents.listen(_onUiIntent);
  }

  void _bindRegistryGroup() {
    final group = context.read<WorkspaceTerminalRegistry>().groupFor(
      widget.tabScopeId,
    );
    if (identical(_group, group)) return;
    _group = group;
    // No group.addListener: shell tabs open on the floating surface; a former
    // setState(() {}) here only dirtied ChatPageShell on every addEntry.
  }

  RunSession? _latestRunPanelSession(List<RunSession> sessions) {
    final runPanelSessions = sessions
        .where(sessionUsesRunPanel)
        .toList(growable: false);
    if (runPanelSessions.isEmpty) return null;
    return runPanelSessions.last;
  }

  List<String> _existingFloatingRunSessionIds(List<WorkbenchTabId> order) {
    return [
      for (final tab in order)
        if (tab.kind == WorkbenchTabKind.run) tab.id,
    ].where((id) => id.isNotEmpty).toList(growable: false);
  }

  void _onUiIntent(RunUiIntent intent) {
    if (!mounted) return;

    if (intent.surface == RunToolSurface.run) {
      final sessions = context.read<RunCubit>().state.sessions;
      final session = _latestRunPanelSession(sessions);
      final runSessionId = session?.id.trim() ?? '';
      if (runSessionId.isNotEmpty) {
        final floating = context.read<FloatingWorkspaceCubit>();
        floating.ensureOpen();
        floating.setActiveWorkspace(widget.workspaceId);
        context
            .read<WorkbenchCubit>()
            .openRun(widget.workspaceId, runSessionId, activate: true);
      }
    } else if (intent.surface == RunToolSurface.terminal) {
      final entryId = intent.terminalEntryId?.trim() ?? '';
      if (entryId.isNotEmpty) {
        final floating = context.read<FloatingWorkspaceCubit>();
        floating.ensureOpen();
        floating.setActiveWorkspace(widget.workspaceId);
        context
            .read<WorkbenchCubit>()
            .openShell(widget.workspaceId, entryId, activate: true);
      }
    }

    if (intent.focusToolWindow && intent.surface == RunToolSurface.terminal) {
      widget.holdHandle?.requestFocus();
    }
    final entryId = intent.terminalEntryId?.trim();
    if (entryId != null &&
        entryId.isNotEmpty &&
        intent.surface == RunToolSurface.terminal) {
      widget.holdHandle?.selectEntry(entryId);
    }
  }

  void _reconcile() {
    final workbench = context.read<WorkbenchCubit>();
    final runCubit = context.read<RunCubit>();
    final runPanelSessions = runCubit.state.sessions
        .where(sessionUsesRunPanel)
        .toList(growable: false);
    final runPanelIds = [
      for (final session in runPanelSessions) session.id,
    ];

    // Stale center run tabs (legacy; floating owns run now).
    final tabOrder = workbench.centerOrder(widget.workspaceId);
    final plan = planWorkbenchShellRunSync(
      tabOrder: tabOrder,
      registryEntryIds: const [],
      runPanelSessionIds: runPanelIds,
    );
    for (final tab in plan.runTabsToRemove) {
      unawaited(workbench.close(widget.workspaceId, tab));
    }

    final floatingStrip = workbench.state.bar(widget.workspaceId).floating;
    final existingFloatingRunIds = _existingFloatingRunSessionIds(
      floatingStrip.order,
    );
    final runIdsToRemove = floatingRunIdsToRemove(
      existingFloatingRunSessionIds: existingFloatingRunIds,
      liveRunPanelSessionIds: runPanelIds,
    );
    final runIdsToEnsure = floatingRunIdsToEnsure(
      existingFloatingRunSessionIds: existingFloatingRunIds,
      liveRunPanelSessionIds: runPanelIds,
    );

    if (!shouldSyncFloatingRuns(
      bridgeWorkspaceId: widget.workspaceId,
      floatingActiveWorkspaceId:
          context.read<FloatingWorkspaceCubit>().state.activeWorkspaceId,
      hasFloatingMutations:
          runIdsToRemove.isNotEmpty || runIdsToEnsure.isNotEmpty,
    )) {
      return;
    }

    for (final id in runIdsToRemove) {
      unawaited(workbench.close(widget.workspaceId, WorkbenchTabId.run(id)));
    }
    for (final id in runIdsToEnsure) {
      workbench.openRun(widget.workspaceId, id, activate: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<RunCubit, RunState>(
      listenWhen: (prev, next) => !identical(prev.sessions, next.sessions),
      listener: (context, state) => _reconcile(),
      child: widget.child,
    );
  }
}
