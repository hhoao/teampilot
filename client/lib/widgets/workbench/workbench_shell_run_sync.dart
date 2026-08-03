import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/floating_workspace/floating_workspace_cubit.dart';
import '../../cubits/floating_workspace/floating_workspace_state.dart';
import '../../cubits/run_cubit.dart';
import '../../cubits/workbench/workbench_cubit.dart';
import '../../models/run/run_session.dart';
import '../../models/run/run_ui_intent.dart';
import '../../services/run/run_panel_session.dart';
import '../../services/terminal/workspace_terminal_registry.dart';
import '../../services/workbench/workbench_run_intent.dart';
import '../../services/workbench/workbench_shell_run_sync_logic.dart';
import '../workspace_terminal_panel.dart';

/// Reconciles RunPanel sessions with floating run tabs and strips stale center
/// run tabs (peer to [WorkbenchSessionSync]).
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
  VoidCallback? _groupListener;

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
    _detachGroupListener();
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
    _detachGroupListener();
    _group = group;
    // Registry still drives hold-handle selection / focus for run→terminal
    // intents; we no longer reconcile shell tabs into WorkbenchCubit.
    _groupListener = () {
      if (!mounted) return;
      setState(() {});
    };
    group.addListener(_groupListener!);
  }

  void _detachGroupListener() {
    final group = _group;
    final listener = _groupListener;
    if (group != null && listener != null) {
      group.removeListener(listener);
    }
    _group = null;
    _groupListener = null;
  }

  RunSession? _latestRunPanelSession(List<RunSession> sessions) {
    final runPanelSessions = sessions
        .where(sessionUsesRunPanel)
        .toList(growable: false);
    if (runPanelSessions.isEmpty) return null;
    return runPanelSessions.last;
  }

  List<String> _existingFloatingRunSessionIds(
    List<FloatingTab> tabs,
  ) {
    return [
      for (final tab in tabs)
        if (tab.surfaceId == 'run') _floatingRunSessionId(tab),
    ].where((id) => id.isNotEmpty).toList(growable: false);
  }

  String _floatingRunSessionId(FloatingTab tab) {
    final payload = tab.payload;
    if (payload is String) {
      final trimmed = payload.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    if (tab.id.startsWith('run:')) {
      return tab.id.substring('run:'.length).trim();
    }
    return '';
  }

  void _onUiIntent(RunUiIntent intent) {
    if (!mounted) return;

    if (intent.surface == RunToolSurface.run) {
      final sessions = context.read<RunCubit>().state.sessions;
      final session = _latestRunPanelSession(sessions);
      final tab = resolveFloatingTabForRunIntent(
        intent,
        runSessionId: session?.id,
        title: session?.owned.configuration.name ?? '',
      );
      if (tab != null) {
        final floating = context.read<FloatingWorkspaceCubit>();
        floating.ensureOpen();
        floating.setActiveWorkspace(widget.workspaceId);
        floating.ensureTab(tab);
        floating.selectTab(tab.id);
      }
    } else if (intent.surface == RunToolSurface.terminal) {
      final group = _group ??
          context.read<WorkspaceTerminalRegistry>().groupFor(widget.tabScopeId);
      final entryId = intent.terminalEntryId?.trim() ?? '';
      final entryTitle = entryId.isEmpty
          ? ''
          : (group.entryById(entryId)?.titleLabel ?? '');
      final floatingTab = resolveFloatingTabForTerminalRunIntent(
        intent,
        entryTitle: entryTitle,
      );
      if (floatingTab != null) {
        final floating = context.read<FloatingWorkspaceCubit>();
        floating.ensureOpen();
        floating.setActiveWorkspace(widget.workspaceId);
        floating.ensureTab(floatingTab);
        floating.selectTab(floatingTab.id);
      }
    }

    final entryId = intent.terminalEntryId?.trim();
    if (entryId != null &&
        entryId.isNotEmpty &&
        intent.surface == RunToolSurface.terminal) {
      widget.holdHandle?.selectEntry(entryId);
    }
    if (intent.focusToolWindow && intent.surface == RunToolSurface.terminal) {
      widget.holdHandle?.requestFocus();
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
    final tabOrder = workbench.tabOrder(widget.workspaceId);
    final plan = planWorkbenchShellRunSync(
      tabOrder: tabOrder,
      registryEntryIds: const [],
      runPanelSessionIds: runPanelIds,
    );

    for (final tab in plan.runTabsToRemove) {
      workbench.removeTab(widget.workspaceId, tab);
    }

    final floating = context.read<FloatingWorkspaceCubit>();
    final bucket =
        floating.state.buckets[widget.workspaceId] ??
        const FloatingWorkspaceBucket();
    final existingFloatingRunIds = _existingFloatingRunSessionIds(bucket.tabs);
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
      floatingActiveWorkspaceId: floating.state.activeWorkspaceId,
      hasFloatingMutations:
          runIdsToRemove.isNotEmpty || runIdsToEnsure.isNotEmpty,
    )) {
      return;
    }

    for (final id in runIdsToRemove) {
      floating.removeTab(floatingRunTabId(id));
    }

    final sessionsById = {for (final session in runPanelSessions) session.id: session};
    for (final id in runIdsToEnsure) {
      final session = sessionsById[id];
      if (session == null) continue;
      final tab = resolveFloatingTabForRunIntent(
        const RunUiIntent(
          surface: RunToolSurface.run,
          activateToolWindow: true,
          focusToolWindow: false,
        ),
        runSessionId: session.id,
        title: session.owned.configuration.name,
      );
      if (tab != null) {
        floating.ensureTab(tab);
      }
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
