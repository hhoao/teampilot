import '../services/cli/installer_types.dart';

/// Live remote workspace / CLI provision status for one roster member.
///
/// Shown on the member terminal pane during launch-time off-home provision.
class MemberRemoteProvisionProgress {
  const MemberRemoteProvisionProgress({
    required this.memberId,
    required this.phase,
    this.detail,
    this.hostLabel = '',
    this.error,
  });

  final String memberId;
  final CliInstallPhase phase;
  final String? detail;

  /// SSH host display (e.g. profile host), for pane subtitle.
  final String hostLabel;

  /// Non-null when provision failed for this member.
  final String? error;

  bool get hasFailed => error != null && error!.trim().isNotEmpty;

  MemberRemoteProvisionProgress copyWith({
    CliInstallPhase? phase,
    String? detail,
    String? hostLabel,
    String? error,
    bool clearError = false,
    bool clearDetail = false,
  }) {
    return MemberRemoteProvisionProgress(
      memberId: memberId,
      phase: phase ?? this.phase,
      detail: clearDetail ? null : (detail ?? this.detail),
      hostLabel: hostLabel ?? this.hostLabel,
      error: clearError ? null : (error ?? this.error),
    );
  }
}
