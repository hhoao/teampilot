import '../../../cli/registry/capabilities/terminal_observation_contributor.dart';
import '../terminal_observation_bus.dart';
import '../terminal_observation_events.dart';
import '../terminal_observation_seat.dart';

/// First / every / turn-start callbacks from [UserLineSubmitted].
final class UserLineModule implements TerminalObservationContributor {
  UserLineModule({
    this.onFirstUserLineSubmitted,
    this.onEveryUserLineSubmitted,
    this.onTurnStart,
  });

  final void Function(String line)? onFirstUserLineSubmitted;
  final void Function(String line)? onEveryUserLineSubmitted;
  final void Function()? onTurnStart;

  @override
  TerminalObservationBinding bind(
    TerminalObservationBus bus,
    TerminalObservationSeat seat,
  ) {
    var firstDone = false;
    final subscription = bus.subscribe<UserLineSubmitted>((event) {
      if (!firstDone) {
        firstDone = true;
        onFirstUserLineSubmitted?.call(event.line);
      }
      onEveryUserLineSubmitted?.call(event.line);
      onTurnStart?.call();
    });
    return CallbackObservationBinding(subscription.cancel);
  }
}
