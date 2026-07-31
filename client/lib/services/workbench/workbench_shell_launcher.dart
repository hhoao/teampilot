import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';

import '../../cubits/chat_cubit.dart';
import '../../cubits/floating_workspace/floating_workspace_cubit.dart';
import '../../cubits/layout_cubit.dart';
import '../../cubits/workbench/workbench_tab.dart';
import '../../models/floating_workspace_tab.dart';
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

/// Resolves the most recent shell from floating terminal tabs (by payload
/// entry id), then falls back to [registryActiveEntryId].
///
/// Center workbench no longer hosts shell tabs after the floating migration —
/// do not use `WorkbenchCubit.resolveMostRecentShell`.
WorkbenchTabId? resolveMostRecentFloatingShell({
  required List<FloatingTab> tabs,
  required String? activeTabId,
  String? registryActiveEntryId,
}) {
  if (activeTabId != null) {
    for (final tab in tabs) {
      if (tab.id != activeTabId || tab.surfaceId != 'terminal') continue;
      final entryId = tab.payload;
      if (entryId is String && entryId.trim().isNotEmpty) {
        return WorkbenchTabId.shell(entryId.trim());
      }
    }
  }
  for (var i = tabs.length - 1; i >= 0; i--) {
    final tab = tabs[i];
    if (tab.surfaceId != 'terminal') continue;
    final entryId = tab.payload;
    if (entryId is String && entryId.trim().isNotEmpty) {
      return WorkbenchTabId.shell(entryId.trim());
    }
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
               SchedulerBinding
                   .instance
                   .platformDispatcher
                   .platformBrightness),
       _sshConnectFailedMessage =
           sshConnectFailedMessage ?? (() => 'SSH connect failed'),
       _termuxConnected = termuxConnected,
       _termuxWorkOpsBlockedMessage = termuxWorkOpsBlockedMessage;

  final FloatingWorkspaceCubit _floating;
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
    final bucket = _floating.state.buckets[workspaceId];
    return resolveMostRecentFloatingShell(
      tabs: bucket?.tabs ?? const <FloatingTab>[],
      activeTabId: bucket?.activeTabId,
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
        _floating.selectTab(floatingShellTabId(existing.id));
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

  /// Opens [spec] via [WorkspaceTerminalSessionOps.openEntry], then ensures and
  /// selects the matching floating terminal tab (snappy UX ahead of sync).
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
    final entry = await _sessionOps.openEntry(
      group: group,
      connector: _connector,
      connectCoordinator: WorkspaceTerminalConnectCoordinator.termuxAware(
        connector: _connector,
        termuxConnected: _termuxConnected,
        termuxWorkOpsBlockedMessage: _termuxWorkOpsBlockedMessage,
      ),
      cwd: trimmedCwd,
      spec: spec,
      theme:
          theme ??
          resolveTerminalThemeFromLayout(
            preferences: _layout.state.preferences,
            platformBrightness: _platformBrightness(),
          ),
      sshConnectFailedMessage:
          sshConnectFailedMessage ?? _sshConnectFailedMessage(),
      select: true,
      followWorkspace: followWorkspace,
      onStateChanged: onStateChanged,
      mounted: mounted,
    );

    final title = entry.titleLabel.trim().isNotEmpty
        ? entry.titleLabel
        : entry.id;
    _floating.ensureOpen();
    _floating.setActiveWorkspace(workspaceId);
    _floating.ensureTab(
      FloatingTab(
        id: floatingShellTabId(entry.id),
        surfaceId: 'terminal',
        title: title,
        payload: entry.id,
      ),
    );
    return entry;
  }
}
