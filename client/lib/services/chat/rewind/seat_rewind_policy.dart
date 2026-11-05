import '../../../models/app_session.dart';
import '../../../models/runtime_target.dart';
import '../../../models/team_config.dart';
import '../../storage/runtime_layout.dart';
import 'seat_rewind_paths.dart';
import 'seat_rewind_store.dart';

/// Why a seat cannot use rewind/fork. UI may map this to a tooltip later.
enum RewindDenial {
  mixedSeatsDisabled,
  mobilePlatform,
  remoteRuntime,
  gitMissing,
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
/// this policy. They previously each carried their own copy of the
/// personal/mobile/local/git conditions.
final class SeatRewindPolicy {
  SeatRewindPolicy({
    required this.isMobile,
    required this.gitAvailable,
    required this.layout,
    required this.launchTargetFor,
  });

  final bool Function() isMobile;
  final bool Function() gitAvailable;
  final RuntimeLayout Function() layout;
  final RuntimeTarget Function(AppSession session, String? memberId)
  launchTargetFor;

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
    if (isMobile()) {
      return const SeatRewindEligibility.denied(RewindDenial.mobilePlatform);
    }
    final launchTarget = launchTargetFor(session, memberId);
    if (launchTarget.kind != RuntimeKind.local) {
      return const SeatRewindEligibility.denied(RewindDenial.remoteRuntime);
    }
    if (!gitAvailable()) {
      return const SeatRewindEligibility.denied(RewindDenial.gitMissing);
    }
    return SeatRewindEligibility.ready(
      SeatRewindStore.forSession(
        layout: layout(),
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
