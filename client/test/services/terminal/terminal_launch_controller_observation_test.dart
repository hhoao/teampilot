import 'dart:typed_data';

import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team/terminal_activity_tracker.dart';
import 'package:teampilot/services/terminal/observation/terminal_observation_bus.dart';
import 'package:teampilot/services/terminal/observation/terminal_observation_events.dart';
import 'package:teampilot/services/terminal/observation/terminal_observation_seat.dart';
import 'package:teampilot/services/terminal/terminal_export.dart';
import 'package:teampilot/services/terminal/terminal_launch_controller.dart';
import 'package:teampilot/services/terminal/terminal_launch_phase.dart';

import '../../support/flush_terminal_engine.dart';
import '../../support/rust_lib_test_init.dart';

void main() {
  setUpAll(initRustLibForTests);

  late TerminalEngine engine;
  late TerminalLaunchController controller;

  setUp(() {
    engine = TerminalEngine(config: TerminalConfig.defaults());
    engine.resize(columns: 40, rows: 5);
    engine.initializeEmpty(5, 40);
    controller = TerminalLaunchController(
      engine: engine,
      activityTracker: TerminalActivityTracker(),
      defaultExecutable: 'claude',
      startupDeadline: const Duration(seconds: 5),
      confirmFallback: const Duration(milliseconds: 50),
      validateLaunch: false,
    );
  });

  tearDown(() {
    controller.dispose();
    engine.dispose();
  });

  test(
    'attachObservation + feedPtyBytes dispatches to observer and feeds engine',
    () async {
      final seen = <int>[];
      final bus = TerminalObservationBus(
        seat: TerminalObservationSeat(
          sessionId: 's',
          memberId: 'm',
          phase: TerminalLaunchPhase.running,
        ),
      );
      bus.addOutputObserver(
        _Capture(seen),
        phases: {TerminalLaunchPhase.running},
      );
      controller.attachObservation(bus);

      controller.feedPtyBytes(Uint8List.fromList('Z'.codeUnits));
      await flushTerminalEngine(engine);

      expect(seen, ['Z'.codeUnitAt(0)]);
      expect(exportTerminalScrollback(engine), contains('Z'));
      bus.dispose();
    },
  );

  test('without attachObservation, feedPtyBytes still feeds the engine', () async {
    controller.feedPtyBytes(Uint8List.fromList('Z'.codeUnits));
    await flushTerminalEngine(engine);
    expect(exportTerminalScrollback(engine), contains('Z'));
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
