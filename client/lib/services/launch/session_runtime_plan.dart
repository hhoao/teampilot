import '../../models/config_bundle.dart';
import '../../models/team_config.dart';

enum SessionRuntimeMode { simple, team }

/// Per-seat launch input for prepare/connect.
///
/// Not the PTY [LaunchPlan] in `shell_launch_spec.dart` — this is the upstream
/// session config (merged bundle + materialized member) for one seat.
class SessionRuntimePlan {
  const SessionRuntimePlan({
    required this.mode,
    required this.workspaceId,
    required this.sessionId,
    required this.memberId,
    required this.expertKey,
    required this.runtimeBundle,
    required this.member,
    this.teamId,
    this.presetId,
  });

  final SessionRuntimeMode mode;
  final String workspaceId;
  final String sessionId;
  final String memberId;
  final String expertKey;
  final String? teamId;
  final String? presetId;
  final ConfigBundle runtimeBundle;
  final TeamMemberConfig member;

  SessionRuntimePlan copyWith({
    SessionRuntimeMode? mode,
    String? workspaceId,
    String? sessionId,
    String? memberId,
    String? expertKey,
    String? teamId,
    String? presetId,
    ConfigBundle? runtimeBundle,
    TeamMemberConfig? member,
  }) {
    return SessionRuntimePlan(
      mode: mode ?? this.mode,
      workspaceId: workspaceId ?? this.workspaceId,
      sessionId: sessionId ?? this.sessionId,
      memberId: memberId ?? this.memberId,
      expertKey: expertKey ?? this.expertKey,
      teamId: teamId ?? this.teamId,
      presetId: presetId ?? this.presetId,
      runtimeBundle: runtimeBundle ?? this.runtimeBundle,
      member: member ?? this.member,
    );
  }
}
