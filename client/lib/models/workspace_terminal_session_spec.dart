import 'package:flutter/foundation.dart';

import 'workspace_folder.dart';
import 'workspace_topology.dart';

/// What machine and shell a workspace-terminal tab runs on (not agent CLIs).
@immutable
sealed class WorkspaceTerminalSessionSpec {
  const WorkspaceTerminalSessionSpec();

  /// Stable key for tab title de-duplication (`Local`, `user@host`, …).
  String get titleBaseKey;

  bool get isLocalControlPlane => switch (this) {
    WorkspaceTerminalLocalSpec() => true,
    _ => false,
  };
}

/// Interactive shell on the TeamPilot host (local PTY / Windows COMSPEC).
@immutable
final class WorkspaceTerminalLocalSpec extends WorkspaceTerminalSessionSpec {
  const WorkspaceTerminalLocalSpec(this.shellPath);

  final String shellPath;

  @override
  String get titleBaseKey => 'local:${shellPath.trim()}';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WorkspaceTerminalLocalSpec && shellPath == other.shellPath;

  @override
  int get hashCode => shellPath.hashCode;
}

/// Shell on a workspace folder target (`local` / `ssh:*` / `wsl:*`).
@immutable
final class WorkspaceTerminalWorkspaceTargetSpec
    extends WorkspaceTerminalSessionSpec {
  const WorkspaceTerminalWorkspaceTargetSpec(this.targetId);

  final String targetId;

  @override
  String get titleBaseKey => 'target:${targetId.trim()}';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WorkspaceTerminalWorkspaceTargetSpec &&
          targetId == other.targetId;

  @override
  int get hashCode => targetId.hashCode;
}

/// Ad-hoc SSH session via a saved profile (may differ from workspace folders).
@immutable
final class WorkspaceTerminalSshProfileSpec extends WorkspaceTerminalSessionSpec {
  const WorkspaceTerminalSshProfileSpec(this.profileId);

  final String profileId;

  @override
  String get titleBaseKey => 'ssh-profile:${profileId.trim()}';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WorkspaceTerminalSshProfileSpec && profileId == other.profileId;

  @override
  int get hashCode => profileId.hashCode;
}

/// Default spec for [cwd] against [folders] (follows active work-plane).
WorkspaceTerminalSessionSpec defaultSessionSpecFor({
  required String cwd,
  required List<WorkspaceFolder> folders,
  required String fallbackLocalShell,
}) {
  final targetId =
      targetIdForFolderPaths(folders, [cwd], matchSubpaths: true) ??
      (folders.isNotEmpty
          ? folders.first.targetId
          : WorkspaceFolder.localTargetId);
  if (targetId == WorkspaceFolder.localTargetId) {
    return WorkspaceTerminalLocalSpec(fallbackLocalShell);
  }
  return WorkspaceTerminalWorkspaceTargetSpec(targetId);
}
