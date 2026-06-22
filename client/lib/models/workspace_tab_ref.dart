import 'package:flutter/foundation.dart';

import '../pages/home_workspace/home_workspace_route.dart';
import 'launch_profile_ref.dart';

/// One title-bar workspace tab: a directory opened under a specific launch identity.
@immutable
class WorkspaceTabRef {
  const WorkspaceTabRef({
    required this.workspaceId,
    required this.identity,
  });

  final String workspaceId;
  final LaunchProfileRef identity;

  static const _sep = '\x1e';

  /// Stable key for UI state, chat buckets, and terminal/tool scopes.
  String get tabKey => '$workspaceId$_sep${identity.profileId}';

  String get route => '/home-v2/workspace/$workspaceId?as=${identity.encode()}';

  static WorkspaceTabRef? fromLocation(String location) {
    final workspaceId = HomeWorkspaceRoute.workspaceId(location);
    final identity = HomeWorkspaceRoute.identity(location);
    if (workspaceId == null || identity == null) return null;
    return WorkspaceTabRef(workspaceId: workspaceId, identity: identity);
  }

  static WorkspaceTabRef? decodeTabKey(String tabKey) {
    final i = tabKey.indexOf(_sep);
    if (i <= 0) return null;
    final workspaceId = tabKey.substring(0, i);
    final identity = LaunchProfileRef.decode(tabKey.substring(i + 1));
    if (identity == null) return null;
    return WorkspaceTabRef(workspaceId: workspaceId, identity: identity);
  }

  factory WorkspaceTabRef.fromJson(Map<String, Object?> json) {
    final workspaceId = (json['workspaceId'] as String?)?.trim() ?? '';
    final identity = LaunchProfileRef.decode(json['as'] as String?);
    if (workspaceId.isEmpty || identity == null) {
      throw FormatException('invalid workspace tab ref: $json');
    }
    return WorkspaceTabRef(workspaceId: workspaceId, identity: identity);
  }

  Map<String, Object?> toJson() => {
        'workspaceId': workspaceId,
        'as': identity.encode(),
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WorkspaceTabRef &&
          runtimeType == other.runtimeType &&
          workspaceId == other.workspaceId &&
          identity == other.identity;

  @override
  int get hashCode => Object.hash(workspaceId, identity);

  @override
  String toString() => 'WorkspaceTabRef($workspaceId, $identity)';
}
