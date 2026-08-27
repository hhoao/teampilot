import 'dart:typed_data';

import 'terminal_observation_seat.dart';

abstract interface class TerminalOutputObserver {
  void onOutput(Uint8List bytes, TerminalObservationSeat seat);
}

abstract interface class TerminalInputObserver {
  void onInput(Uint8List bytes, TerminalObservationSeat seat);
}

abstract interface class TerminalInputTransform {
  int get order;
  Uint8List transform(Uint8List bytes, TerminalObservationSeat seat);
}

abstract interface class TerminalScreenObserver {
  void onPainted(TerminalObservationSeat seat);
}

abstract interface class TerminalObservationSubscription {
  void cancel();
}

sealed class TerminalDerivedEvent {
  const TerminalDerivedEvent();
}

final class OscTitle extends TerminalDerivedEvent {
  const OscTitle(this.title);
  final String title;
}

final class UserLineSubmitted extends TerminalDerivedEvent {
  const UserLineSubmitted(this.line);
  final String line;
}
