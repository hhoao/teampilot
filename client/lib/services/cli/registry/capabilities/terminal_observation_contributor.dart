import '../../../terminal/observation/terminal_observation_bus.dart';
import '../../../terminal/observation/terminal_observation_seat.dart';

abstract interface class TerminalObservationContributor {
  TerminalObservationBinding bind(
    TerminalObservationBus bus,
    TerminalObservationSeat seat,
  );
}

abstract interface class TerminalObservationBinding {
  void unbind();
}

final class CallbackObservationBinding implements TerminalObservationBinding {
  CallbackObservationBinding(this._unbind);
  final void Function() _unbind;
  var _done = false;
  @override
  void unbind() {
    if (_done) return;
    _done = true;
    _unbind();
  }
}

final class CompositeObservationBinding implements TerminalObservationBinding {
  CompositeObservationBinding(this._parts);
  final List<TerminalObservationBinding> _parts;
  @override
  void unbind() {
    for (final part in _parts) {
      part.unbind();
    }
  }
}
