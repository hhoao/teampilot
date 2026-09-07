import 'package:flutter/foundation.dart';

import '../../models/workspace_folder.dart';
import '../../models/workspace_terminal_session_spec.dart';
import '../../models/workspace_topology.dart';
import '../../repositories/ssh_profile_repository.dart';
import '../../widgets/workspace_folder_directory_row.dart';
import '../host/host_interactive_shell.dart';
import '../terminal/workspace_shell_connector.dart';

enum WorkspaceTerminalLaunchAction { openSession, newSshProfile, settings }

@immutable
class WorkspaceTerminalLaunchMenuItem {
  const WorkspaceTerminalLaunchMenuItem.session({
    required this.spec,
    required this.label,
    this.launchCwd,
  }) : action = WorkspaceTerminalLaunchAction.openSession,
       isDivider = false;

  const WorkspaceTerminalLaunchMenuItem.divider()
    : spec = null,
      label = '',
      launchCwd = null,
      action = WorkspaceTerminalLaunchAction.openSession,
      isDivider = true;

  const WorkspaceTerminalLaunchMenuItem.newSsh()
    : spec = null,
      label = '',
      launchCwd = null,
      action = WorkspaceTerminalLaunchAction.newSshProfile,
      isDivider = false;

  const WorkspaceTerminalLaunchMenuItem.settings()
    : spec = null,
      label = '',
      launchCwd = null,
      action = WorkspaceTerminalLaunchAction.settings,
      isDivider = false;

  final WorkspaceTerminalSessionSpec? spec;
  final String label;
  final WorkspaceTerminalLaunchAction action;
  final bool isDivider;

  /// Folder-pinned launch directory (multi-root workspaces). Null means the
  /// caller's default cwd (workspace primary folder / synced cwd).
  final String? launchCwd;
}

/// IDEA-style “+ ▾” menu: local shells, workspace targets, SSH profiles.
abstract final class WorkspaceTerminalLaunchCatalog {
  WorkspaceTerminalLaunchCatalog._();

  static List<WorkspaceTerminalLaunchMenuItem> buildLocalShells([
    List<WorkspaceFolder> folders = const [],
  ]) {
    final items = <WorkspaceTerminalLaunchMenuItem>[];
    final shells = HostInteractiveShell.discoverSpecs();
    final (extras, allLocalPaths) = _extraLocalFolderPaths(folders);
    for (final shell in shells) {
      items.add(
        WorkspaceTerminalLaunchMenuItem.session(
          spec: WorkspaceTerminalLocalSpec(shell.executable),
          label: shell.menuLabel,
        ),
      );
      for (final extra in extras) {
        items.add(
          WorkspaceTerminalLaunchMenuItem.session(
            spec: WorkspaceTerminalLocalSpec(shell.executable),
            label: '${shell.menuLabel} · ${_folderLabel(extra, allLocalPaths)}',
            launchCwd: extra,
          ),
        );
      }
    }
    return items;
  }

  static Future<List<WorkspaceTerminalLaunchMenuItem>> build({
    required List<WorkspaceFolder> folders,
    required SshProfileRepository sshProfiles,
    required WorkspaceShellConnector connector,
  }) async {
    final items = buildLocalShells(folders);
    final remoteTargets = workspaceTargetIds(folders)
        .where((id) => id != WorkspaceFolder.localTargetId)
        .toList(growable: false);
    if (remoteTargets.isNotEmpty) {
      items.add(const WorkspaceTerminalLaunchMenuItem.divider());
      for (final targetId in remoteTargets) {
        final spec = WorkspaceTerminalWorkspaceTargetSpec(targetId);
        final label = await connector.labelForSpec(spec);
        items.add(
          WorkspaceTerminalLaunchMenuItem.session(spec: spec, label: label),
        );
      }
    }

    final profiles = await sshProfiles.loadAll();
    items.add(const WorkspaceTerminalLaunchMenuItem.divider());
    items.add(WorkspaceTerminalLaunchMenuItem.newSsh());
    for (final profile in profiles) {
      items.add(
        WorkspaceTerminalLaunchMenuItem.session(
          spec: WorkspaceTerminalSshProfileSpec(profile.id),
          label: profile.hostIdentifier,
        ),
      );
    }

    items.add(const WorkspaceTerminalLaunchMenuItem.divider());
    items.add(WorkspaceTerminalLaunchMenuItem.settings());
    return items;
  }

  /// Local folder paths after the primary (first local) folder, de-duped.
  ///
  /// Returns `(extras, allLocalPaths)` — label collision checks need basenames
  /// across the full local folder set, primary included.
  static (List<String>, List<String>) _extraLocalFolderPaths(
    List<WorkspaceFolder> folders,
  ) {
    final seen = <String>{};
    final all = <String>[];
    final extras = <String>[];
    var primarySeen = false;
    for (final folder in folders) {
      if (folder.targetId != WorkspaceFolder.localTargetId) continue;
      final path = folder.path.trim();
      if (path.isEmpty || !seen.add(path)) continue;
      all.add(path);
      if (!primarySeen) {
        primarySeen = true;
        continue;
      }
      extras.add(path);
    }
    return (extras, all);
  }

  /// Basename per extra folder; falls back to the full path when basenames
  /// collide across the workspace's local folders (primary included).
  static String _folderLabel(String path, List<String> allLocalPaths) {
    final base = workspacePathBasename(path);
    final collisions = allLocalPaths
        .map(workspacePathBasename)
        .where((b) => b == base)
        .length;
    return collisions > 1 ? path : base;
  }
}
