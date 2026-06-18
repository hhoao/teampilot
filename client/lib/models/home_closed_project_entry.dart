import 'package:flutter/foundation.dart';

@immutable
class HomeClosedWorkspaceEntry {
  const HomeClosedWorkspaceEntry({
    required this.projectId,
    required this.displayName,
    this.primaryPath = '',
    this.closedAt = 0,
  });

  factory HomeClosedWorkspaceEntry.fromJson(Map<String, Object?> json) {
    return HomeClosedWorkspaceEntry(
      projectId: json['projectId'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      primaryPath: json['primaryPath'] as String? ?? '',
      closedAt: json['closedAt'] as int? ?? 0,
    );
  }

  final String projectId;
  final String displayName;
  final String primaryPath;
  final int closedAt;

  Map<String, Object?> toJson() => {
    'projectId': projectId,
    'displayName': displayName,
    'primaryPath': primaryPath,
    'closedAt': closedAt,
  };
}
