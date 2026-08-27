import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/terminal/observation/modules/launch_start_module.dart';
import 'package:teampilot/services/terminal/observation/terminal_observation_bus.dart';
import 'package:teampilot/services/terminal/observation/terminal_observation_seat.dart';
import 'package:teampilot/services/terminal/terminal_launch_phase.dart';

void main() {
  late TerminalObservationSeat seat;
  late TerminalObservationBus bus;

  tearDown(() => bus.dispose());

  test('fatal startup chunk fails and does not confirm', () {
    final failures = <String>[];
    var confirmed = 0;
    seat = TerminalObservationSeat(
      sessionId: 's',
      memberId: 'm',
      phase: TerminalLaunchPhase.confirming,
      startupExecutable: 'claude',
      validateLaunch: false,
      failLaunch: failures.add,
      confirmStarted: () => confirmed++,
    );
    bus = TerminalObservationBus(seat: seat);
    LaunchStartModule().bind(bus, seat);
    bus.dispatchOutput(
      Uint8List.fromList(
        utf8.encode('cannot be used with root/sudo privileges'),
      ),
    );
    expect(failures, isNotEmpty);
    expect(confirmed, 0);
  });

  test('healthy starting chunk confirms and does not fail', () {
    var confirmed = 0;
    seat = TerminalObservationSeat(
      sessionId: 's',
      memberId: 'm',
      phase: TerminalLaunchPhase.confirming,
      confirmStarted: () => confirmed++,
      failLaunch: (_) {},
    );
    bus = TerminalObservationBus(seat: seat);
    LaunchStartModule().bind(bus, seat);
    bus.dispatchOutput(Uint8List.fromList(utf8.encode('ready')));
    expect(confirmed, 1);
  });

  test('process exit while starting fails launch', () {
    final failures = <String>[];
    seat = TerminalObservationSeat(
      sessionId: 's',
      memberId: 'm',
      phase: TerminalLaunchPhase.confirming,
      failLaunch: failures.add,
      confirmStarted: () {},
    );
    bus = TerminalObservationBus(seat: seat);
    LaunchStartModule().bind(bus, seat);
    bus.notifyProcessExited(1);
    expect(failures, ['[process exited with code 1 during startup]']);
  });
}
