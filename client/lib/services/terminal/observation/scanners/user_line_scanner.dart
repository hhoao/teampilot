import 'dart:convert';
import 'dart:typed_data';

import '../../../../utils/terminal/every_user_line_capture.dart';
import '../terminal_observation_events.dart';
import '../terminal_observation_seat.dart';

/// L1 user-line scanner. Wraps [EveryUserLineCapture]; installed on first
/// [UserLineSubmitted] subscriber. Must see original input bytes.
final class UserLineScanner implements TerminalInputObserver {
  UserLineScanner({required void Function(UserLineSubmitted event) emit})
    : _emit = emit {
    _capture = EveryUserLineCapture(_onSubmitted);
  }

  final void Function(UserLineSubmitted event) _emit;
  late EveryUserLineCapture _capture;

  @override
  void onInput(Uint8List bytes, TerminalObservationSeat seat) {
    if (bytes.isEmpty) return;
    _capture.feed(utf8.decode(bytes, allowMalformed: true));
  }

  void reset() {
    _capture = EveryUserLineCapture(_onSubmitted);
  }

  void _onSubmitted(String line) => _emit(UserLineSubmitted(line));
}
