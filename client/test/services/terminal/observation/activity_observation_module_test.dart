import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team/terminal_activity_tracker.dart';
import 'package:teampilot/services/terminal/observation/modules/activity_observation_module.dart';
import 'package:teampilot/services/terminal/observation/terminal_observation_bus.dart';
import 'package:teampilot/services/terminal/observation/terminal_observation_seat.dart';
import 'package:teampilot/services/terminal/terminal_launch_phase.dart';

void main() {
  late TerminalObservationSeat seat;
  late TerminalObservationBus bus;

  tearDown(() => bus.dispose());

  test('running chunks fingerprint; confirming chunks do not', () {
    final tracker = _SpyTracker();
    seat = TerminalObservationSeat(
      sessionId: 's',
      memberId: 'm',
      phase: TerminalLaunchPhase.confirming,
      activityTracker: tracker,
    );
    bus = TerminalObservationBus(seat: seat);
    ActivityObservationModule().bind(bus, seat);
    bus.dispatchOutput(Uint8List.fromList(utf8.encode('boot')));
    expect(tracker.notes, 0);
    bus.setPhase(TerminalLaunchPhase.running);
    bus.dispatchOutput(Uint8List.fromList(utf8.encode('hello world\n')));
    expect(tracker.notes, 1);
  });

  test('unbind stops activity notes', () {
    final tracker = _SpyTracker();
    seat = TerminalObservationSeat(
      sessionId: 's',
      memberId: 'm',
      phase: TerminalLaunchPhase.running,
      activityTracker: tracker,
    );
    bus = TerminalObservationBus(seat: seat);
    ActivityObservationModule().bind(bus, seat).unbind();
    bus.dispatchOutput(Uint8List.fromList(utf8.encode('hello world\n')));
    expect(tracker.notes, 0);
  });
}

class _SpyTracker extends TerminalActivityTracker {
  int notes = 0;

  @override
  void notePtyBytes(List<int> bytes, [DateTime? at]) {
    notes++;
    super.notePtyBytes(bytes, at);
  }
}
