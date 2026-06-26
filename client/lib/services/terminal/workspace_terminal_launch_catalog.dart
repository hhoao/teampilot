import 'package:flutter/foundation.dart';

import '../../models/workspace_folder.dart';
import '../../models/workspace_terminal_session_spec.dart';
import '../../models/workspace_topology.dart';
import '../../repositories/ssh_profile_repository.dart';
import '../terminal/workspace_interactive_shell.dart';
import '../terminal/workspace_shell_connector.dart';

enum WorkspaceTerminalLaunchAction {
  openSession,
  newSshProfile,
  settings,
}

@immutable
class WorkspaceTerminalLaunchMenuItem {
  const WorkspaceTerminalLaunchMenuItem.session({
    required this.spec,
    required this.label,
  }) : action = WorkspaceTerminalLaunchAction.openSession,
       isDivider = false;

  const WorkspaceTerminalLaunchMenuItem.divider()
    : spec = null,
      label = '',
      action = WorkspaceTerminalLaunchAction.openSession,
      isDivider = true;

  const WorkspaceTerminalLaunchMenuItem.newSsh()
    : spec = null,
      label = '',
      action = WorkspaceTerminalLaunchAction.newSshProfile,
      isDivider = false;

  const WorkspaceTerminalLaunchMenuItem.settings()
    : spec = null,
      label = '',
      action = WorkspaceTerminalLaunchAction.settings,
      isDivider = false;

  final WorkspaceTerminalSessionSpec? spec;
  final String label;
  final WorkspaceTerminalLaunchAction action;
  final bool isDivider;
}

/// IDEA-style “+ ▾” menu: local shells, workspace targets, SSH profiles.
abstract final class WorkspaceTerminalLaunchCatalog {
  WorkspaceTerminalLaunchCatalog._();

  static List<WorkspaceTerminalLaunchMenuItem> buildLocalShells() {
    final items = <WorkspaceTerminalLaunchMenuItem>[];
    for (final shellPath in WorkspaceInteractiveShell.discoverShellPaths()) {
      items.add(
        WorkspaceTerminalLaunchMenuItem.session(
          spec: WorkspaceTerminalLocalSpec(shellPath),
          label: WorkspaceInteractiveShell.menuLabelFor(shellPath),
        ),
      );
    }
    return items;
  }

  static Future<List<WorkspaceTerminalLaunchMenuItem>> build({
    required List<WorkspaceFolder> folders,
    required SshProfileRepository sshProfiles,
    required WorkspaceShellConnector connector,
  }) async {
    final items = buildLocalShells();
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
    items.add(
      WorkspaceTerminalLaunchMenuItem.settings(),
    );
    return items;
  }
}
