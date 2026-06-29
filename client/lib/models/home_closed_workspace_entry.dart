import 'package:flutter/foundation.dart';

import 'launch_profile_ref.dart';
import 'workspace_tab_ref.dart';
import 'workspace_topology.dart';

@immutable
class HomeClosedWorkspaceEntry {
  const HomeClosedWorkspaceEntry({
    required this.workspaceId,
    required this.displayName,
    required this.identity,
    this.primaryPath = '',
    this.closedAt = 0,
    this.topology,
  });

  factory HomeClosedWorkspaceEntry.fromJson(Map<String, Object?> json) {
    final workspaceId = json['workspaceId'] as String? ?? '';
    final identity = LaunchProfileRef.decode(json['as'] as String?);
    if (workspaceId.isEmpty || identity == null) {
      throw FormatException('invalid closed workspace entry: $json');
    }
    return HomeClosedWorkspaceEntry(
      workspaceId: workspaceId,
      displayName: json['displayName'] as String? ?? '',
      primaryPath: json['primaryPath'] as String? ?? '',
      closedAt: json['closedAt'] as int? ?? 0,
      identity: identity,
      topology: _decodeTopology(json['topology'] as String?),
    );
  }

  factory HomeClosedWorkspaceEntry.fromTab(
    WorkspaceTabRef tab, {
    required String displayName,
    String primaryPath = '',
    WorkspaceTopology? topology,
  }) =>
      HomeClosedWorkspaceEntry(
        workspaceId: tab.workspaceId,
        displayName: displayName,
        primaryPath: primaryPath,
        identity: tab.identity,
        topology: topology,
      );

  final String workspaceId;
  final String displayName;
  final String primaryPath;
  final int closedAt;
  final LaunchProfileRef identity;

  /// Snapshot at close time when the workspace record may later disappear.
  final WorkspaceTopology? topology;

  String get tabKey => WorkspaceTabRef(
        workspaceId: workspaceId,
        identity: identity,
      ).tabKey;

  Map<String, Object?> toJson() => {
        'workspaceId': workspaceId,
        'displayName': displayName,
        'primaryPath': primaryPath,
        'closedAt': closedAt,
        'as': identity.encode(),
        if (topology != null) 'topology': topology!.name,
      };

  static WorkspaceTopology? _decodeTopology(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return null;
    for (final candidate in WorkspaceTopology.values) {
      if (candidate.name == value) return candidate;
    }
    return null;
  }
}
