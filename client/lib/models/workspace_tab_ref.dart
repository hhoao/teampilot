import 'package:flutter/foundation.dart';

import '../pages/home_workspace/home_workspace_route.dart';

/// One title-bar workspace tab keyed by directory only.
@immutable
class WorkspaceTabRef {
  const WorkspaceTabRef({required this.workspaceId});

  final String workspaceId;

  /// Stable key for UI state, chat buckets, and terminal/tool scopes.
  String get tabKey => workspaceId;

  String get route => '/home-v2/workspace/$workspaceId';

  static WorkspaceTabRef? fromLocation(String location) {
    final workspaceId = HomeWorkspaceRoute.workspaceId(location);
    if (workspaceId == null || workspaceId.trim().isEmpty) return null;
    return WorkspaceTabRef(workspaceId: workspaceId);
  }

  factory WorkspaceTabRef.fromJson(Map<String, Object?> json) {
    final workspaceId = (json['workspaceId'] as String?)?.trim() ?? '';
    if (workspaceId.isEmpty) {
      throw FormatException('invalid workspace tab ref: $json');
    }
    return WorkspaceTabRef(workspaceId: workspaceId);
  }

  Map<String, Object?> toJson() => {'workspaceId': workspaceId};

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WorkspaceTabRef &&
          runtimeType == other.runtimeType &&
          workspaceId == other.workspaceId;

  @override
  int get hashCode => workspaceId.hashCode;

  @override
  String toString() => 'WorkspaceTabRef($workspaceId)';
}
