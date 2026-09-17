import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/services/ssh/mcp/session_ssh_mcp_constants.dart';
import 'package:teampilot/services/ssh/mcp/session_ssh_mcp_targets.dart';

import '../../../resource/contribution/prompt_document.dart';
import '../../../resource/contribution/resource_origin.dart';
import '../../../resource/providers/prompt_contribution_provider.dart';
import '../cli_capability.dart';
import '../launch/cli_launch_arg_contribution.dart';
import '../launch/cli_launch_arg_provider.dart';
import '../launch/cli_launch_context.dart';
import '../launch/workspace_access.dart';

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
) => [
  for (final target in targets) WorkspaceRemoteFolderInfo.fromTarget(target),
];

WorkspaceBaseInfoPromptInputs workspaceBaseInfoPromptInputs({
  Map<String, Map<String, Object?>>? extraMcpServers,
  List<WorkspaceFolder> folders = const [],
  SshProfile? Function(String id)? profileOf,
}) {
  final injected = extraMcpServers?[sessionSshMcpServerName] != null;
  final remotes = profileOf == null
      ? const <WorkspaceRemoteFolderInfo>[]
      : workspaceRemoteFoldersFromTargets(
          sessionSshMcpTargetsFromFolders(
            folders: folders,
            profileOf: profileOf,
          ),
        );
  return WorkspaceBaseInfoPromptInputs(
    sshMcpInjected: injected,
    remoteFolders: remotes,
  );
}

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

const workspaceBaseInfoProviderId = 'workspace-base-info';

abstract interface class WorkspaceBaseInfoCapability
    implements
        CliCapability,
        CliLaunchArgProvider,
        PromptContributionProvider {}

abstract base class WorkspaceBaseInfoCapabilityBase
    implements WorkspaceBaseInfoCapability {
  const WorkspaceBaseInfoCapabilityBase();

  @override
  String get providerId => workspaceBaseInfoProviderId;

  Iterable<CliLaunchArgContribution> buildWorkspaceAccessArgs(
    CliLaunchContext context,
    WorkspaceAccess access,
  );

  @override
  Iterable<CliLaunchArgContribution> buildLaunchArgs(CliLaunchContext context) {
    final access = WorkspaceAccess.fromContext(context);
    if (access.isEmpty) return const [];
    return buildWorkspaceAccessArgs(context, access);
  }

  @override
  FutureOr<Iterable<PromptContribution>> provide(
    PromptProviderContext context,
  ) {
    final inputs = context.workspaceBaseInfo;
    final snapshot = WorkspaceSeatSnapshot(
      sameHostExtraDirs: [
        for (final directory in context.additionalDirectories)
          if (directory.trim().isNotEmpty) directory.trim(),
      ],
      sshMcpInjected: inputs.sshMcpInjected,
      remoteFolders: inputs.remoteFolders,
      customPromptSections: inputs.customPromptSections,
    );
    final content = composeWorkspaceBaseInfoPrompt(snapshot);
    if (content.isEmpty) return const [];
    return [
      PromptContribution(
        id: workspaceBaseInfoProviderId,
        title: 'Workspace',
        content: content,
        scope: PromptScope.workspace,
        mergeRole: PromptMergeRole.append,
        origin: const ContributionOrigin(
          providerId: workspaceBaseInfoProviderId,
          kind: ResourceOriginKind.cliBuiltIn,
          sourceId: workspaceBaseInfoProviderId,
        ),
      ),
    ];
  }
}
