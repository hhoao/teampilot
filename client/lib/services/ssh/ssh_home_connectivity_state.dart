import 'dart:async';

import 'package:flutter/foundation.dart';

export 'ssh_connection_gate.dart' show SshIoGuard;

/// Canonical lifecycle phase of one SSH home/profile. Deliberately has no
/// `down`: the codebase already has two different `down` values
/// (SshConnectionGateState.down, RemoteConnectionStatus.down).
enum SshPhase {
  idle,
  connecting,
  up,
  degraded,
  reconnecting,
  unreachable,
  suspended,
  failed,
}

/// Why a home stopped; surfaced so the user knows whether to re-pair, fix
/// credentials, or just retry.
enum SshFailureKind {
  hostIdentityChanged,
  authFailed,
  transportError,
  unknown,
}

/// The single source of truth for "is this home connected".
@immutable
class SshHomeConnectivityState {
  const SshHomeConnectivityState({
    required this.profileId,
    this.phase = SshPhase.idle,
    this.failure,
    this.errorDetail,
    this.attempt = 0,
    this.storageLive = false,
    this.planeRebinding = false,
  });

  /// The one atomic transition into "connected". Clearing failure/errorDetail/
  /// attempt in the same value is what stops the "需要重新连接" banner from
  /// sticking after a successful home switch (invariant 3). Never build an
  /// `up` state with the generic constructor.
  factory SshHomeConnectivityState.up(String profileId) =>
      SshHomeConnectivityState(
        profileId: profileId,
        phase: SshPhase.up,
        storageLive: true,
      );

  final String profileId;
  final SshPhase phase;
  final SshFailureKind? failure;
  final String? errorDetail;

  /// 1-based retry number; 0 when no retry is running.
  final int attempt;

  /// The durable truth: a usable storage lease exists.
  final bool storageLive;

  /// UI hold during a home storage plane rebind; NOT connectivity truth.
  final bool planeRebinding;

  bool get isUp => phase == SshPhase.up;

  bool get isDown =>
      phase == SshPhase.unreachable ||
      phase == SshPhase.suspended ||
      phase == SshPhase.failed;

  bool get retryActive => phase == SshPhase.reconnecting;

  SshHomeConnectivityState copyWith({
    String? profileId,
    SshPhase? phase,
    SshFailureKind? failure,
    String? errorDetail,
    int? attempt,
    bool? storageLive,
    bool? planeRebinding,
    bool clearFailure = false,
    bool clearErrorDetail = false,
  }) => SshHomeConnectivityState(
    profileId: profileId ?? this.profileId,
    phase: phase ?? this.phase,
    failure: clearFailure ? null : (failure ?? this.failure),
    errorDetail: clearErrorDetail ? null : (errorDetail ?? this.errorDetail),
    attempt: attempt ?? this.attempt,
    storageLive: storageLive ?? this.storageLive,
    planeRebinding: planeRebinding ?? this.planeRebinding,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SshHomeConnectivityState &&
          profileId == other.profileId &&
          phase == other.phase &&
          failure == other.failure &&
          errorDetail == other.errorDetail &&
          attempt == other.attempt &&
          storageLive == other.storageLive &&
          planeRebinding == other.planeRebinding;

  @override
  int get hashCode => Object.hash(
    profileId,
    phase,
    failure,
    errorDetail,
    attempt,
    storageLive,
    planeRebinding,
  );

  @override
  String toString() =>
      'SshHomeConnectivityState($profileId, ${phase.name}, '
      'live=$storageLive, attempt=$attempt, failure=${failure?.name}, '
      'rebind=$planeRebinding)';
}

/// Narrow read port consumed by cubits. Implemented by
/// SshHomeConnectivitySupervisor in production and by a test double in tests,
/// so cubit tests never need a real factory/coordinator to drive UI state.
abstract class SshConnectivitySource {
  Stream<SshHomeConnectivityState> get changes;
  SshHomeConnectivityState stateFor(String profileId);
}
