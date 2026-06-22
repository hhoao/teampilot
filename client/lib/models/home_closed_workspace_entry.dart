import 'package:flutter/foundation.dart';

import 'launch_profile_ref.dart';
import 'workspace_tab_ref.dart';

@immutable
class HomeClosedWorkspaceEntry {
  const HomeClosedWorkspaceEntry({
    required this.workspaceId,
    required this.displayName,
    required this.identity,
    this.primaryPath = '',
    this.closedAt = 0,
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
    );
  }

  factory HomeClosedWorkspaceEntry.fromTab(
    WorkspaceTabRef tab, {
    required String displayName,
    String primaryPath = '',
  }) =>
      HomeClosedWorkspaceEntry(
        workspaceId: tab.workspaceId,
        displayName: displayName,
        primaryPath: primaryPath,
        identity: tab.identity,
      );

  final String workspaceId;
  final String displayName;
  final String primaryPath;
  final int closedAt;
  final LaunchProfileRef identity;

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
      };
}
