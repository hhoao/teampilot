import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';

import '../../cubits/chat_cubit.dart';
import '../../cubits/floating_workspace/floating_workspace_cubit.dart';
import '../../cubits/layout_cubit.dart';
import '../../cubits/workbench/workbench_cubit.dart';
import '../../cubits/workbench/workbench_tab.dart';
import '../../models/runtime_target.dart';
import '../../models/workspace_folder.dart';
import '../../models/workspace_terminal_session_spec.dart';
import '../host/host_interactive_shell.dart';
import '../terminal/terminal_theme_for_launch.dart';
import '../terminal/workspace_shell_connector.dart';
import '../terminal/workspace_terminal_connect_coordinator.dart';
import '../terminal/workspace_terminal_registry.dart';
import '../terminal/workspace_terminal_session_ops.dart';

/// Outcome of a create-or-focus shell command (e.g. [CommandIds.togglePanel]).
enum WorkbenchShellToggleAction { selectExisting, createDefault }

/// Pure plan for focusing an existing shell tab or creating a default one.
class WorkbenchShellTogglePlan {
  const WorkbenchShellTogglePlan._({
    required this.workspaceId,
    required this.action,
    this.existing,
  });

  factory WorkbenchShellTogglePlan.select({
    required String workspaceId,
    required WorkbenchTabId existing,
  }) => WorkbenchShellTogglePlan._(
    workspaceId: workspaceId,
    action: WorkbenchShellToggleAction.selectExisting,
    existing: existing,
  );

  factory WorkbenchShellTogglePlan.create({required String workspaceId}) =>
      WorkbenchShellTogglePlan._(
        workspaceId: workspaceId,
        action: WorkbenchShellToggleAction.createDefault,
      );

  final String workspaceId;
  final WorkbenchShellToggleAction action;
  final WorkbenchTabId? existing;
}

/// Floating terminal tab id for a registry [entryId].
String floatingShellTabId(String entryId) => 'shell:$entryId';

/// Resolves the most recent shell from the floating strip ([order]), then
/// falls back to [registryActiveEntryId].
///
/// The strip's [activeId] wins; otherwise the last `shell` tab; otherwise the
/// registry's active entry id. Center workbench no longer hosts shell tabs
/// after the floating migration.
WorkbenchTabId? resolveMostRecentFloatingShell({
  required List<WorkbenchTabId> order,
  required WorkbenchTabId? activeId,
  String? registryActiveEntryId,
}) {
  if (activeId != null && activeId.kind == WorkbenchTabKind.shell) {
    final entryId = activeId.id.trim();
    if (entryId.isNotEmpty) return activeId;
  }
  for (var i = order.length - 1; i >= 0; i--) {
    final tab = order[i];
    if (tab.kind != WorkbenchTabKind.shell) continue;
    final entryId = tab.id.trim();
    if (entryId.isNotEmpty) return tab;
  }
  final reg = registryActiveEntryId?.trim() ?? '';
  if (reg.isNotEmpty) return WorkbenchTabId.shell(reg);
  return null;
}

/// Resolves whether [togglePanel] should select an existing shell or create one.
///
/// Returns null when [workspaceId] is empty (no active workspace).
WorkbenchShellTogglePlan? resolveWorkbenchShellToggle({
  required String workspaceId,
  required WorkbenchTabId? Function(String workspaceId) resolveMostRecentShell,
}) {
  final id = workspaceId.trim();
  if (id.isEmpty) return null;
  final existing = resolveMostRecentShell(id);
  if (existing != null) {
    return WorkbenchShellTogglePlan.select(workspaceId: id, existing: existing);
  }
  return WorkbenchShellTogglePlan.create(workspaceId: id);
}

/// Context-less create/focus path for workspace shell tabs (commands + strip).
///
/// Active workspace comes from [ChatCubit.tabStore.activeWorkspaceId] (the
/// title-bar tab key; equals [Workspace.workspaceId] for normal workspace
/// pages). Terminal registry groups use the same id as [tabScopeId].
///
/// Shell UI lives on the floating terminal surface — not the center strip.
class WorkbenchShellLauncher {
  WorkbenchShellLauncher({
    required FloatingWorkspaceCubit floating,
    required WorkbenchCubit workbench,
    required ChatCubit chat,
    required WorkspaceTerminalRegistry registry,
    required WorkspaceShellConnector connector,
    required LayoutCubit layout,
    WorkspaceTerminalSessionOps? sessionOps,
    String Function()? fallbackLocalShell,
    RuntimeTarget Function()? homeTarget,
    Brightness Function()? platformBrightness,
    String Function()? sshConnectFailedMessage,
    bool Function()? termuxConnected,
    String Function()? termuxWorkOpsBlockedMessage,
  }) : _floating = floating,
       _workbench = workbench,
       _chat = chat,
       _registry = registry,
       _connector = connector,
       _layout = layout,
       _sessionOps = sessionOps ?? WorkspaceTerminalSessionOps(),
       _fallbackLocalShell =
           fallbackLocalShell ?? HostInteractiveShell.defaultExecutable,
       _homeTarget = homeTarget ?? RuntimeTarget.local,
       _platformBrightness =
           platformBrightness ??
           (() =>
               SchedulerBinding.instance.platformDispatcher.platformBrightness),
       _sshConnectFailedMessage =
           sshConnectFailedMessage ?? (() => 'SSH connect failed'),
       _termuxConnected = termuxConnected,
       _termuxWorkOpsBlockedMessage = termuxWorkOpsBlockedMessage;

  final FloatingWorkspaceCubit _floating;
  final WorkbenchCubit _workbench;
  final ChatCubit _chat;
  final WorkspaceTerminalRegistry _registry;
  final WorkspaceShellConnector _connector;
  final LayoutCubit _layout;
  final WorkspaceTerminalSessionOps _sessionOps;
  final String Function() _fallbackLocalShell;
  final RuntimeTarget Function() _homeTarget;
  final Brightness Function() _platformBrightness;
  final String Function() _sshConnectFailedMessage;
  final bool Function()? _termuxConnected;
  final String Function()? _termuxWorkOpsBlockedMessage;

  WorkbenchTabId? _resolveMostRecentShell(String workspaceId) {
    final strip = _workbench.state.bar(workspaceId).floating;
    return resolveMostRecentFloatingShell(
      order: strip.order,
      activeId: strip.activeId,
      registryActiveEntryId: _registry.groupFor(workspaceId).activeId,
    );
  }

  /// Focus most-recent shell, or open a default local/SSH/WSL shell for cwd.
  Future<void> focusOrCreateDefaultShell() async {
    final workspaceId = _chat.tabStore.activeWorkspaceId.trim();
    final plan = resolveWorkbenchShellToggle(
      workspaceId: workspaceId,
      resolveMostRecentShell: _resolveMostRecentShell,
    );
    if (plan == null) return;

    if (plan.action == WorkbenchShellToggleAction.selectExisting) {
      final existing = plan.existing;
      if (existing != null) {
        _floating.ensureOpen();
        _floating.setActiveWorkspace(plan.workspaceId);
        _workbench.activate(plan.workspaceId, existing);
      }
      return;
    }

    final workspace = _chat.state.workspaces
        .where((w) => w.workspaceId == plan.workspaceId)
        .firstOrNull;
    final cwd = workspace?.firstFolderPath.trim() ?? '';
    if (cwd.isEmpty) return;

    final folders = workspace?.folders ?? const <WorkspaceFolder>[];
    final spec = defaultSessionSpecFor(
      cwd: cwd,
      folders: folders,
      fallbackLocalShell: _fallbackLocalShell(),
      home: _homeTarget(),
    );
    await openAndSelect(
      workspaceId: plan.workspaceId,
      tabScopeId: plan.workspaceId,
      cwd: cwd,
      spec: spec,
    );
  }

  /// Creates the registry entry, shows the floating tab immediately, then
  /// connects the transport on the next frame (snappy UX ahead of sync).
  Future<WorkspaceTerminalEntry?> openAndSelect({
    required String workspaceId,
    required String tabScopeId,
    required String cwd,
    required WorkspaceTerminalSessionSpec spec,
    TerminalTheme? theme,
    String? sshConnectFailedMessage,
    bool followWorkspace = true,
    VoidCallback? onStateChanged,
    bool Function()? mounted,
  }) async {
    final trimmedCwd = cwd.trim();
    if (trimmedCwd.isEmpty) return null;

    final group = _registry.groupFor(tabScopeId);
    final entry = await _sessionOps.createEntry(
      group: group,
      connector: _connector,
      cwd: trimmedCwd,
      spec: spec,
      select: true,
      followWorkspace: followWorkspace,
    );

    // Empty→first-tab UI is deferred one frame in FloatingWorkspacePanel so
    // connect must wait an extra frame on that path. Check the *target*
    // workspace's floating strip (the current active workspace may differ).
    final deferFirstTabUi =
        _workbench.state.bar(workspaceId).floating.order.isEmpty;
    _floating.ensureOpen();
    _floating.setActiveWorkspace(workspaceId);
    _workbench.openShell(workspaceId, entry.id, activate: true);

    final resolvedTheme =
        theme ??
        resolveTerminalThemeFromLayout(
          preferences: _layout.state.preferences,
          platformBrightness: _platformBrightness(),
        );
    final sshFailed = sshConnectFailedMessage ?? _sshConnectFailedMessage();
    final coordinator = WorkspaceTerminalConnectCoordinator.termuxAware(
      connector: _connector,
      termuxConnected: _termuxConnected,
      termuxWorkOpsBlockedMessage: _termuxWorkOpsBlockedMessage,
    );

    void scheduleConnect() {
      unawaited(
        _sessionOps.connectEntry(
          group: group,
          entry: entry,
          connectCoordinator: coordinator,
          theme: resolvedTheme,
          sshConnectFailedMessage: sshFailed,
          onStateChanged: onStateChanged,
          mounted: mounted,
        ),
      );
    }

    // Connect after the floating tab's first painted frame — not before ensureTab.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (deferFirstTabUi) {
        SchedulerBinding.instance.addPostFrameCallback(
          (_) => scheduleConnect(),
        );
      } else {
        scheduleConnect();
      }
    });
    return entry;
  }
}
