import 'package:flutter/foundation.dart';

import '../services/storage/launch_profile_provisioner.dart';
import 'app_session.dart';
import 'launch_profile_kind.dart';
import 'launch_profile_ref.dart';
import 'workspace_tab_ref.dart';

/// Isolation key for automations — mirrors [WorkspaceTabRef] without UI routing.
@immutable
class AutomationTabScope {
  const AutomationTabScope({
    required this.workspaceId,
    required this.launchProfileId,
  });

  final String workspaceId;
  final String launchProfileId;

  /// Same separator as [WorkspaceTabRef.tabKey].
  static const tabKeySeparator = '\x1e';

  String get tabKey => '$workspaceId$tabKeySeparator$launchProfileId';

  factory AutomationTabScope.fromWorkspaceTab(WorkspaceTabRef tab) {
    return AutomationTabScope(
      workspaceId: tab.workspaceId,
      launchProfileId: LaunchProfileProvisioner.defaultPersonalId,
    );
  }

  factory AutomationTabScope.fromJson(Map<String, Object?> json) {
    final workspaceId = (json['workspaceId'] as String?)?.trim() ?? '';
    final launchProfileId = (json['as'] as String?)?.trim() ?? '';
    if (workspaceId.isEmpty || launchProfileId.isEmpty) {
      throw FormatException('invalid automation tab scope: $json');
    }
    return AutomationTabScope(
      workspaceId: workspaceId,
      launchProfileId: launchProfileId,
    );
  }

  /// Derives the tab scope that owns [session] automations.
  factory AutomationTabScope.fromSession(AppSession session) {
    final team = session.sessionTeam.trim();
    if (team.isEmpty) {
      final profileId = session.profileId.trim();
      return AutomationTabScope(
        workspaceId: session.workspaceId,
        launchProfileId: profileId.isNotEmpty
            ? profileId
            : LaunchProfileProvisioner.defaultPersonalId,
      );
    }
    return AutomationTabScope(
      workspaceId: session.workspaceId,
      launchProfileId: team,
    );
  }

  Map<String, Object?> toJson() => {
        'workspaceId': workspaceId,
        'as': launchProfileId,
      };

  /// Whether [session] belongs to this tab scope (same rule as sidebar filtering).
  bool ownsSession(AppSession session, LaunchProfileKind launchKind) {
    if (session.workspaceId != workspaceId) return false;
    return session.sessionTeam.trim() == sessionTeamFilterForKind(launchKind);
  }

  /// Chat / sidebar session-team filter for this scope when [kind] is known.
  String sessionTeamFilterForKind(LaunchProfileKind kind) {
    return kind == LaunchProfileKind.personal ? '' : launchProfileId;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AutomationTabScope &&
          runtimeType == other.runtimeType &&
          workspaceId == other.workspaceId &&
          launchProfileId == other.launchProfileId;

  @override
  int get hashCode => Object.hash(workspaceId, launchProfileId);

  @override
  String toString() => 'AutomationTabScope($workspaceId, $launchProfileId)';
}

extension AutomationTabScopeLaunchProfile on AutomationTabScope {
  LaunchProfileRef get identity => LaunchProfileRef(launchProfileId);
}
