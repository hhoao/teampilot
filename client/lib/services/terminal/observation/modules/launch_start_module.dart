import 'dart:convert';
import 'dart:typed_data';

import '../../../cli/registry/capabilities/terminal_observation_contributor.dart';
import '../../terminal_launch_phase.dart';
import '../../terminal_startup_failure_detector.dart';
import '../terminal_observation_bus.dart';
import '../terminal_observation_events.dart';
import '../terminal_observation_seat.dart';

/// Classifies startup PTY output and process exit before the seat is running.
final class LaunchStartModule implements TerminalObservationContributor {
  @override
  TerminalObservationBinding bind(
    TerminalObservationBus bus,
    TerminalObservationSeat seat,
  ) {
    final startupOutput = StringBuffer();
    final outputSubscription = bus.addOutputObserver(
      _LaunchStartOutputObserver(startupOutput),
      phases: {TerminalLaunchPhase.spawning, TerminalLaunchPhase.confirming},
    );
    final exitSubscription = bus.addProcessExitObserver((code) {
      if (seat.phase != TerminalLaunchPhase.spawning &&
          seat.phase != TerminalLaunchPhase.confirming) {
        return;
      }
      final classified = _classifyStartupFailure(
        startupOutput.toString(),
        seat,
      );
      seat.failLaunch?.call(
        classified ??
            (code == 0
                ? '[process exited unexpectedly during startup]'
                : '[process exited with code $code during startup]'),
      );
    });
    return CallbackObservationBinding(() {
      outputSubscription.cancel();
      exitSubscription.cancel();
    });
  }
}

final class _LaunchStartOutputObserver implements TerminalOutputObserver {
  _LaunchStartOutputObserver(this._startupOutput);

  final StringBuffer _startupOutput;

  @override
  void onOutput(Uint8List bytes, TerminalObservationSeat seat) {
    _startupOutput.write(utf8.decode(bytes, allowMalformed: true));
    final classified = _classifyStartupFailure(_startupOutput.toString(), seat);
    if (classified != null) {
      seat.failLaunch?.call(classified);
      return;
    }
    seat.confirmStarted?.call();
  }
}

String? _classifyStartupFailure(String text, TerminalObservationSeat seat) {
  try {
    return TerminalStartupFailureDetector.classifyStartupFailure(
      text,
      executable: seat.startupExecutable,
      validateLaunch: seat.validateLaunch,
    );
  } on Object {
    return null;
  }
}
