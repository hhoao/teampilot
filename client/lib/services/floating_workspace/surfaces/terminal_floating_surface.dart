import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../cubits/chat_cubit.dart';
import '../../../cubits/floating_workspace/floating_workspace_cubit.dart';
import '../../../l10n/l10n_compat.dart';
import '../../../models/floating_workspace_tab.dart';
import '../../../models/workbench_shell_descriptor.dart';
import '../../../pages/workbench/shell_terminal_surface.dart';
import '../../../services/workbench/workbench_shell_actions.dart';
import '../../../services/workbench/workbench_shell_launcher.dart';
import '../../../utils/logging/logger.dart';
import '../../commands/command_ids.dart';
import '../../terminal/workspace_terminal_registry.dart';
import '../../terminal/workspace_terminal_run_service.dart';
import '../floating_surface.dart';
import '../floating_terminal_pty_hold_scope.dart';

/// Floating surface that hosts a workspace shell terminal for one entry id.
///
/// Domain open is driven by [WorkbenchShellLauncher]; [activate] selects the
/// registry entry so the shared panel shows the right PTY. Persisted tabs
/// (no live entry yet) rebuild their PTY on first body mount.
class TerminalFloatingSurface extends FloatingSurface {
  TerminalFloatingSurface({
    required FloatingWorkspaceCubit floating,
    required WorkspaceTerminalRegistry registry,
    required WorkspaceTerminalRunService runService,
    WorkbenchShellDescriptor? Function(String workspaceId, String tabId)?
    descriptorFor,
    Future<void> Function({
      required String workspaceId,
      required String tabId,
      required WorkbenchShellDescriptor descriptor,
    })?
    restoreTab,
  }) : _floating = floating,
       _registry = registry,
       _runService = runService,
       _descriptorFor = descriptorFor,
       _restoreTab = restoreTab;

  final FloatingWorkspaceCubit _floating;
  final WorkspaceTerminalRegistry _registry;
  final WorkspaceTerminalRunService _runService;
  final WorkbenchShellDescriptor? Function(String workspaceId, String tabId)?
  _descriptorFor;
  final Future<void> Function({
    required String workspaceId,
    required String tabId,
    required WorkbenchShellDescriptor descriptor,
  })?
  _restoreTab;

  /// Tab id → in-flight restore. One attempt per tab even if the body rebuilds
  /// or remounts mid-restore; cleared on completion so a retry can re-run.
  final Map<String, Future<bool>> _restoring = {};

  @override
  String get id => 'terminal';

  @override
  FloatingEmptyAction? get emptyAction => const FloatingEmptyAction(
    commandId: CommandIds.floatingNewTerminal,
    labelKey: 'newTerminal',
    icon: Icons.terminal_outlined,
  );

  @override
  bool get allowMultipleTabs => true;

  @override
  FloatingTab createTab({required String workspaceId, Object? payload}) {
    final entryId = payload is String ? payload.trim() : '';
    final label = entryId.isEmpty
        ? ''
        : (_registry.groupFor(workspaceId).entryById(entryId)?.titleLabel ??
              '');
    final persistedTitle = entryId.isEmpty
        ? ''
        : _titleForDescriptor(_descriptorFor?.call(workspaceId, entryId));
    final title = label.trim().isNotEmpty
        ? label
        : (persistedTitle.isNotEmpty
              ? persistedTitle
              : (entryId.isEmpty ? 'Terminal' : entryId));
    return FloatingTab(
      id: entryId.isEmpty ? 'shell:' : floatingShellTabId(entryId),
      surfaceId: id,
      title: title,
      payload: entryId.isEmpty ? null : entryId,
    );
  }

  static String _titleForDescriptor(WorkbenchShellDescriptor? descriptor) {
    final cwd = descriptor?.cwd.trim().replaceAll('\\', '/') ?? '';
    if (cwd.isEmpty) return '';
    final segments = cwd.split('/').where((s) => s.isNotEmpty);
    return segments.isEmpty ? '' : segments.last;
  }

  @override
  Widget build(BuildContext context, FloatingTab tab) {
    final entryId = tab.payload;
    if (entryId is! String || entryId.isEmpty) {
      return const SizedBox.shrink();
    }
    final workspaceId = _floating.state.activeWorkspaceId;
    if (workspaceId.isEmpty) {
      return const SizedBox.shrink();
    }
    final group = _registry.groupFor(workspaceId);
    final entry = group.entryById(entryId);
    if (entry == null) {
      final descriptor = _descriptorFor?.call(workspaceId, entryId);
      if (descriptor == null) return const SizedBox.shrink();
      return _RestoringTerminalBody(
        key: ValueKey('restoring-$entryId'),
        restore: () => _attemptRestore(workspaceId, entryId, descriptor),
      );
    }
    final cwd = entry.cwd.trim().isNotEmpty
        ? entry.cwd
        : (context
                  .read<ChatCubit>()
                  .state
                  .workspaces
                  .where((w) => w.workspaceId == workspaceId)
                  .firstOrNull
                  ?.firstFolderPath
                  .trim() ??
              '');
    if (cwd.isEmpty) {
      return const SizedBox.shrink();
    }
    return ShellTerminalSurface(
      workspaceId: workspaceId,
      tabScopeId: workspaceId,
      workingDirectory: cwd,
      holdHandle: FloatingTerminalPtyHoldScope.maybeOf(context),
      activeEntryId: entryId,
    );
  }

  Future<bool> _attemptRestore(
    String workspaceId,
    String tabId,
    WorkbenchShellDescriptor descriptor,
  ) {
    final restore = _restoreTab;
    if (restore == null) return Future<bool>.value(false);
    final existing = _restoring[tabId];
    if (existing != null) return existing;
    final future = () async {
      try {
        await restore(
          workspaceId: workspaceId,
          tabId: tabId,
          descriptor: descriptor,
        );
        return true;
      } on Object catch (e, st) {
        appLogger.w('[floating-shell] restore failed ($tabId): $e\n$st');
        return false;
      }
    }();
    _restoring[tabId] = future;
    unawaited(future.whenComplete(() => _restoring.remove(tabId)));
    return future;
  }

  @override
  Future<void> activate(FloatingTab tab) async {
    final entryId = tab.payload;
    if (entryId is! String || entryId.isEmpty) return;
    final workspaceId = _floating.state.activeWorkspaceId;
    if (workspaceId.isEmpty) return;
    final group = _registry.groupFor(workspaceId);
    if (group.entryById(entryId) == null) return;
    group.activeId = entryId;
  }

  @override
  Future<bool> canClose(FloatingTab tab, {BuildContext? context}) async => true;

  @override
  void onTabClosed(FloatingTab tab) {
    final entryId = tab.payload;
    if (entryId is! String || entryId.isEmpty) return;
    final workspaceId = _floating.state.activeWorkspaceId;
    if (workspaceId.isEmpty) return;
    disposeWorkbenchShellDomain(
      runService: _runService,
      group: _registry.groupFor(workspaceId),
      entryId: entryId,
    );
  }
}

/// Placeholder while a persisted shell tab rebuilds its PTY. Owns the trigger
/// (one per tab body) and the retry affordance when entry creation throws.
class _RestoringTerminalBody extends StatefulWidget {
  const _RestoringTerminalBody({required this.restore, super.key});

  final Future<bool> Function() restore;

  @override
  State<_RestoringTerminalBody> createState() => _RestoringTerminalBodyState();
}

class _RestoringTerminalBodyState extends State<_RestoringTerminalBody> {
  var _started = false;
  var _failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    if (!mounted || _started) return;
    _started = true;
    final ok = await widget.restore();
    if (!mounted) return;
    if (!ok) setState(() => _failed = true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    if (_failed) {
      return Center(
        child: TextButton(
          onPressed: () {
            setState(() {
              _failed = false;
              _started = false;
            });
            _start();
          },
          child: Text(l10n.retry),
        ),
      );
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.workspace.terminalRestoring,
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
