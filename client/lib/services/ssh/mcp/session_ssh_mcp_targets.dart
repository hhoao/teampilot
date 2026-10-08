import 'package:flutter/foundation.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/models/workspace_folder.dart';

@immutable
class SessionSshMcpTarget {
  SessionSshMcpTarget({
    required this.profile,
    required List<String> folderPaths,
  }) : folderPaths = List.unmodifiable(folderPaths);

  final SshProfile profile;
  final List<String> folderPaths;
}

List<SessionSshMcpTarget> sessionSshMcpTargetsFromFolders({
  required List<WorkspaceFolder> folders,
  required SshProfile? Function(String id) profileOf,
}) {
  final order = <String>[];
  final profiles = <String, SshProfile>{};
  final pathsByProfile = <String, List<String>>{};

  for (final folder in folders) {
    if (runtimeKindOfId(folder.targetId) != RuntimeKind.ssh) continue;
    final profileId = sshProfileIdOfId(folder.targetId);
    if (profileId == null) continue;
    final profile = profileOf(profileId);
    if (profile == null) continue;

    profiles.putIfAbsent(profileId, () {
      order.add(profileId);
      return profile;
    });
    pathsByProfile.putIfAbsent(profileId, () => []).add(folder.path);
  }

  return [
    for (final id in order)
      SessionSshMcpTarget(
        profile: profiles[id]!,
        folderPaths: pathsByProfile[id]!,
      ),
  ];
}

/// Resolves [connectionName] to a target: profile id first, then a unique
/// display name. Null, empty, or whitespace-only names match only when
/// [targets] contains exactly one entry; otherwise null.
SessionSshMcpTarget? resolveSessionSshMcpConnection(
  List<SessionSshMcpTarget> targets,
  String? connectionName,
) {
  final trimmed = connectionName?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return targets.length == 1 ? targets.first : null;
  }

  for (final target in targets) {
    if (target.profile.id == trimmed) return target;
  }

  SessionSshMcpTarget? nameMatch;
  var nameMatchCount = 0;
  for (final target in targets) {
    if (target.profile.name == trimmed) {
      nameMatch = target;
      nameMatchCount++;
      if (nameMatchCount > 1) return null;
    }
  }
  return nameMatchCount == 1 ? nameMatch : null;
}
