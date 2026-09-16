import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/services/io/filesystem.dart';

import 'session_ssh_mcp_operations.dart';
import 'session_ssh_mcp_targets.dart';
import 'session_ssh_mcp_transport.dart';

/// Pure resolver: session + workspace + profiles → [SessionSshMcpContext].
SessionSshMcpContext resolveSessionSshMcpContext({
  required AppSession session,
  required Workspace workspace,
  required SshProfile? Function(String id) profileOf,
  required Filesystem localFs,
  required bool localUsesPosixPaths,
  String? memberId,
}) {
  return SessionSshMcpContext(
    enabled: shouldInjectSessionSshMcp(
      workspace: workspace,
      launchKind: RuntimeKind.local,
    ),
    targets: sessionSshMcpTargetsFromFolders(
      folders: workspace.folders,
      profileOf: profileOf,
    ),
    localAllowedRoots: _localAllowedRoots(
      folders: workspace.folders,
      session: session,
      usesPosixPaths: localUsesPosixPaths,
      memberId: memberId,
    ),
    localUsesPosixPaths: localUsesPosixPaths,
    localFs: localFs,
  );
}

List<String> _localAllowedRoots({
  required List<WorkspaceFolder> folders,
  required AppSession session,
  required bool usesPosixPaths,
  String? memberId,
}) {
  final roots = <String>[];
  final seen = <String>{};

  void add(String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty || seen.contains(trimmed)) return;
    seen.add(trimmed);
    roots.add(trimmed);
  }

  for (final folder in folders) {
    if (folder.targetId == WorkspaceFolder.localTargetId) {
      add(folder.path);
    }
  }

  final trimmedMember = memberId?.trim();
  if (trimmedMember != null && trimmedMember.isNotEmpty) {
    final work = session.workDirsForMember(
      trimmedMember,
      folders: folders,
      usesPosixPaths: usesPosixPaths,
    );
    add(work.workingDirectory);
    for (final dir in work.addDirs) {
      add(dir);
    }
  }

  return roots;
}
