import 'package:flutter/foundation.dart';
import 'package:teampilot/services/ssh/mcp/session_ssh_mcp_targets.dart';

@immutable
class WorkspaceRemoteFolderInfo {
  const WorkspaceRemoteFolderInfo({
    required this.profileId,
    required this.name,
    required this.endpoint,
    required this.folderPaths,
  });

  factory WorkspaceRemoteFolderInfo.fromTarget(SessionSshMcpTarget target) {
    final profile = target.profile;
    return WorkspaceRemoteFolderInfo(
      profileId: profile.id,
      name: profile.name,
      endpoint: '${profile.username}@${profile.host}:${profile.port}',
      folderPaths: target.folderPaths,
    );
  }

  final String profileId;
  final String name;
  final String endpoint;
  final List<String> folderPaths;
}

@immutable
class WorkspaceBaseInfoPromptInputs {
  const WorkspaceBaseInfoPromptInputs({
    this.sshMcpInjected = false,
    this.remoteFolders = const [],
    this.customPromptSections = const [],
  });

  static const empty = WorkspaceBaseInfoPromptInputs();

  final bool sshMcpInjected;
  final List<WorkspaceRemoteFolderInfo> remoteFolders;
  final List<String> customPromptSections;
}

@immutable
class WorkspaceSeatSnapshot {
  const WorkspaceSeatSnapshot({
    this.cwd,
    this.sameHostExtraDirs = const [],
    this.remoteFolders = const [],
    this.sshMcpInjected = false,
    this.customPromptSections = const [],
  });

  final String? cwd;
  final List<String> sameHostExtraDirs;
  final List<WorkspaceRemoteFolderInfo> remoteFolders;
  final bool sshMcpInjected;
  final List<String> customPromptSections;
}

List<WorkspaceRemoteFolderInfo> workspaceRemoteFoldersFromTargets(
  Iterable<SessionSshMcpTarget> targets,
) => [for (final target in targets) WorkspaceRemoteFolderInfo.fromTarget(target)];

String composeWorkspaceBaseInfoPrompt(WorkspaceSeatSnapshot snapshot) {
  final extras = [
    for (final dir in snapshot.sameHostExtraDirs)
      if (dir.trim().isNotEmpty) dir.trim(),
  ];
  final sections = <String>[];
  if (extras.isNotEmpty) {
    final body = StringBuffer(
      '## Workspace directories\n'
      'This session can also access the following directories on the same host.\n'
      'They are already authorized. Use absolute paths.\n',
    );
    for (final dir in extras) {
      body.writeln('- $dir');
    }
    sections.add(body.toString().trim());
  }
  if (snapshot.sshMcpInjected) {
    final body = StringBuffer(
      '## Remote projects\n'
      'This workspace also includes project directories on other hosts.\n'
      'They are not on this machine — do not treat them as local paths.\n'
      'Use the `ssh` MCP: call `list-servers` for the current snapshot, then\n'
      '`execute-command`, `upload`, or `download` with `connectionName` set to a\n'
      '`profileId` from that list.\n',
    );
    for (final remote in snapshot.remoteFolders) {
      final label = remote.name.trim().isEmpty
          ? '`${remote.profileId}`'
          : '${remote.name} (`${remote.profileId}`)';
      final paths = remote.folderPaths
          .map((path) => path.trim())
          .where((path) => path.isNotEmpty)
          .join(', ');
      body.writeln(
        paths.isEmpty
            ? '- $label at ${remote.endpoint}'
            : '- $label at ${remote.endpoint} — $paths',
      );
    }
    sections.add(body.toString().trim());
  }
  for (final custom in snapshot.customPromptSections) {
    final trimmed = custom.trim();
    if (trimmed.isNotEmpty) sections.add(trimmed);
  }
  return sections.join('\n\n');
}
