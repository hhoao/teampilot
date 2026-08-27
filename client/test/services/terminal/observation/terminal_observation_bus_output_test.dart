import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/terminal/observation/terminal_observation_bus.dart';
import 'package:teampilot/services/terminal/observation/terminal_observation_events.dart';
import 'package:teampilot/services/terminal/observation/terminal_observation_seat.dart';
import 'package:teampilot/services/terminal/terminal_launch_controller.dart';

void main() {
  late TerminalObservationSeat seat;
  late TerminalObservationBus bus;

  setUp(() {
    seat = TerminalObservationSeat(
      sessionId: 's',
      memberId: 'm',
      phase: TerminalLaunchPhase.running,
    );
    bus = TerminalObservationBus(seat: seat);
  });

  tearDown(() => bus.dispose());

  test('two observers see the same chunk; mutation does not leak', () {
    final seen = <int>[];
    bus.addOutputObserver(
      _Capture(seen),
      phases: {TerminalLaunchPhase.running},
    );
    bus.addOutputObserver(
      _MutateThenCapture(seen),
      phases: {TerminalLaunchPhase.running},
    );
    bus.dispatchOutput(Uint8List.fromList([1, 2, 3]));
    expect(seen, [1, 1]);
  });

  test('throwing observer does not skip later observers', () {
    final later = <int>[];
    bus.addOutputObserver(_Throwing(), phases: {TerminalLaunchPhase.running});
    bus.addOutputObserver(
      _Capture(later),
      phases: {TerminalLaunchPhase.running},
    );
    bus.dispatchOutput(Uint8List.fromList([9]));
    expect(later, [9]);
  });

  test('observer phase filter skips non-matching chunks', () {
    final seen = <int>[];
    bus.addOutputObserver(
      _Capture(seen),
      phases: {TerminalLaunchPhase.confirming},
    );
    bus.dispatchOutput(Uint8List.fromList([1]));
    expect(seen, isEmpty);
    bus.setPhase(TerminalLaunchPhase.confirming);
    bus.dispatchOutput(Uint8List.fromList([2]));
    expect(seen, [2]);
  });

  test('phase change during dispatch applies on the next chunk', () {
    final running = <int>[];
    bus.setPhase(TerminalLaunchPhase.confirming);
    bus.addOutputObserver(
      _PhaseFlip(bus),
      phases: {TerminalLaunchPhase.confirming},
    );
    bus.addOutputObserver(
      _Capture(running),
      phases: {TerminalLaunchPhase.running},
    );
    bus.dispatchOutput(Uint8List.fromList([1]));
    expect(running, isEmpty);
    bus.dispatchOutput(Uint8List.fromList([2]));
    expect(running, [2]);
  });

  test('dispatch after dispose is a no-op', () {
    final seen = <int>[];
    bus.addOutputObserver(
      _Capture(seen),
      phases: {TerminalLaunchPhase.running},
    );
    bus.dispose();
    bus.dispatchOutput(Uint8List.fromList([1]));
    expect(seen, isEmpty);
  });

  test('empty chunks are ignored', () {
    var calls = 0;
    bus.addOutputObserver(
      _Callback((_) => calls++),
      phases: {TerminalLaunchPhase.running},
    );
    bus.dispatchOutput(Uint8List(0));
    expect(calls, 0);
  });
}

final class _Capture implements TerminalOutputObserver {
  _Capture(this.seen);
  final List<int> seen;

  @override
  void onOutput(Uint8List bytes, TerminalObservationSeat seat) {
    seen.add(bytes[0]);
  }
}

final class _MutateThenCapture implements TerminalOutputObserver {
  _MutateThenCapture(this.seen);
  final List<int> seen;

  @override
  void onOutput(Uint8List bytes, TerminalObservationSeat seat) {
    try {
      bytes[0] = 99;
    } on Object {
      // Unmodifiable view rejects in-place writes.
    }
    seen.add(bytes[0]);
  }
}

final class _Throwing implements TerminalOutputObserver {
  @override
  void onOutput(Uint8List bytes, TerminalObservationSeat seat) {
    throw StateError('observer failed');
  }
}

final class _PhaseFlip implements TerminalOutputObserver {
  _PhaseFlip(this.bus);
  final TerminalObservationBus bus;

  @override
  void onOutput(Uint8List bytes, TerminalObservationSeat seat) {
    bus.setPhase(TerminalLaunchPhase.running);
  }
}

final class _Callback implements TerminalOutputObserver {
  _Callback(this._onOutput);
  final void Function(Uint8List bytes) _onOutput;

  @override
  void onOutput(Uint8List bytes, TerminalObservationSeat seat) {
    _onOutput(bytes);
  }
}
