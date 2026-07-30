import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/run_cubit.dart';
import '../../cubits/workbench/workbench_cubit.dart';
import '../../cubits/workbench/workbench_tab.dart';
import '../../models/run/run_ui_intent.dart';
import '../../services/run/run_panel_session.dart';
import '../../services/terminal/workspace_terminal_registry.dart';
import '../../services/workbench/workbench_run_intent.dart';
import '../../services/workbench/workbench_shell_run_sync_logic.dart';
import '../workspace_terminal_panel.dart';

/// Passively mirrors RunPanel sessions into the center workbench strip
/// (peer to [WorkbenchSessionSync]).
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

  void _onUiIntent(RunUiIntent intent) {
    if (!mounted) return;
    final workbench = context.read<WorkbenchCubit>();
    final sessions = context.read<RunCubit>().state.sessions;
    final runPanelSessions = sessions
        .where(sessionUsesRunPanel)
        .toList(growable: false);
    final latestRunId = runPanelSessions.isEmpty
        ? null
        : runPanelSessions.last.id;
    final tab = resolveWorkbenchTabForRunIntent(
      intent,
      latestRunSessionId: latestRunId,
    );
    if (tab != null) {
      workbench.ensureTab(widget.workspaceId, tab);
      workbench.select(widget.workspaceId, tab);
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
    final runPanelIds = context
        .read<RunCubit>()
        .state
        .sessions
        .where(sessionUsesRunPanel)
        .map((s) => s.id)
        .toList(growable: false);
    final tabOrder = workbench.tabOrder(widget.workspaceId);
    final plan = planWorkbenchShellRunSync(
      tabOrder: tabOrder,
      registryEntryIds: const [],
      runPanelSessionIds: runPanelIds,
    );
    if (plan.isEmpty) return;

    for (final tab in plan.runTabsToRemove) {
      workbench.removeTab(widget.workspaceId, tab);
    }

    if (plan.runIdsToEnsureAndSelect.isEmpty) return;

    WorkbenchTabId? lastRun;
    for (final id in plan.runIdsToEnsureAndSelect) {
      lastRun = WorkbenchTabId.run(id);
      workbench.ensureTab(widget.workspaceId, lastRun);
    }
    if (lastRun != null) {
      workbench.select(widget.workspaceId, lastRun);
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
