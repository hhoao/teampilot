import '../../../models/app_session.dart';
import '../../../models/runtime_target.dart';
import '../../../models/team_config.dart';
import '../../storage/runtime_context.dart';
import 'rewind_capability.dart';
import 'seat_rewind_paths.dart';
import 'seat_rewind_store.dart';

/// Why a seat cannot use rewind/fork. UI may map this to a tooltip later.
enum RewindDenial {
  mixedSeatsDisabled,
  workPlaneNotReady,
  gitMissing,
  unsupportedBackend,
}

/// Result of evaluating one seat: either a denial or a ready-to-use store.
final class SeatRewindEligibility {
  const SeatRewindEligibility._({this.denial, this.store});

  const SeatRewindEligibility.denied(RewindDenial denial)
    : this._(denial: denial);

  const SeatRewindEligibility.ready(SeatRewindStore store)
    : this._(store: store);

  final RewindDenial? denial;
  final SeatRewindStore? store;

  bool get allowed => denial == null && store != null;
}

/// One pure place for "can this seat be rewound, and which repo does it use?".
///
/// Checkpoint writers, the history host, and the ACP attach path must all ask
/// this policy. Work-plane context and git capability are resolved before
/// [evaluate] (see `ChatCubit.prepareRewindFor`) and read synchronously here,
/// so checkpoint writers that run ahead of the async prime still work.
final class SeatRewindPolicy {
  SeatRewindPolicy({
    required this.workTargetFor,
    required this.contextFor,
    required this.capabilityFor,
  });

  final RuntimeTarget Function(AppSession session, String? memberId)
  workTargetFor;
  final RuntimeContext? Function(RuntimeTarget target) contextFor;
  final RewindCapability Function(RuntimeTarget target) capabilityFor;

  /// Resolves the work-plane context for a session/seat for callers that need
  /// the [RuntimeContext] itself (e.g. building a fork destination store).
  RuntimeContext? contextForSession(AppSession session, String? memberId) =>
      contextFor(workTargetFor(session, memberId));

  SeatRewindEligibility evaluate({
    required AppSession session,
    required String? memberId,
    required CliTool cli,
    required bool acp,
    bool allowMixed = false,
  }) {
    if (!allowMixed && !session.isSimple && !kMixedSeatRewindEnabled) {
      return const SeatRewindEligibility.denied(
        RewindDenial.mixedSeatsDisabled,
      );
    }
    final target = workTargetFor(session, memberId);
    final ctx = contextFor(target);
    if (ctx == null) {
      return const SeatRewindEligibility.denied(
        RewindDenial.workPlaneNotReady,
      );
    }
    if (target.kind == RuntimeKind.ssh && target.remoteOs == RemoteOs.windows) {
      return const SeatRewindEligibility.denied(
        RewindDenial.unsupportedBackend,
      );
    }
    final cap = capabilityFor(target);
    if (!cap.available) {
      return const SeatRewindEligibility.denied(RewindDenial.gitMissing);
    }
    return SeatRewindEligibility.ready(
      SeatRewindStore.forContext(
        context: ctx,
        workspaceId: session.workspaceId,
        sessionId: session.sessionId,
        target: resolveSeatRewindTarget(
          personal: session.isSimple,
          acp: acp,
          tool: cli.value,
          memberId: memberId,
        ),
      ),
    );
  }
}
