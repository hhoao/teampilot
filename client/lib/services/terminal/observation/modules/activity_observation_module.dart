import 'dart:typed_data';

import '../../../cli/registry/capabilities/terminal_observation_contributor.dart';
import '../../terminal_launch_phase.dart';
import '../terminal_observation_bus.dart';
import '../terminal_observation_events.dart';
import '../terminal_observation_seat.dart';

/// Forwards running-phase PTY bytes to the seat activity tracker.
final class ActivityObservationModule
    implements TerminalObservationContributor {
  @override
  TerminalObservationBinding bind(
    TerminalObservationBus bus,
    TerminalObservationSeat seat,
  ) {
    final subscription = bus.addOutputObserver(
      const _ActivityOutputObserver(),
      phases: {TerminalLaunchPhase.running},
    );
    return CallbackObservationBinding(subscription.cancel);
  }
}

final class _ActivityOutputObserver implements TerminalOutputObserver {
  const _ActivityOutputObserver();

  @override
  void onOutput(Uint8List bytes, TerminalObservationSeat seat) {
    seat.activityTracker?.notePtyBytes(bytes);
  }
}
