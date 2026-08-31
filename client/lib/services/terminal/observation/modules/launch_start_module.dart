import 'dart:convert';
import 'dart:typed_data';

import '../../../../utils/logging/logger.dart';
import '../../../cli/registry/capabilities/terminal_observation_contributor.dart';
import '../../process_exit_failure_message.dart';
import '../../terminal_launch_phase.dart';
import '../../terminal_startup_failure_detector.dart';
import '../terminal_observation_bus.dart';
import '../terminal_observation_events.dart';
import '../terminal_observation_seat.dart';

/// Classifies startup PTY output and process exit before the seat is running.
final class LaunchStartModule implements TerminalObservationContributor {
  LaunchStartModule({
    String? Function(
      String text, {
      required String executable,
      required bool validateLaunch,
    })?
    classify,
  }) : _classify =
           classify ?? TerminalStartupFailureDetector.classifyStartupFailure;

  final String? Function(
    String text, {
    required String executable,
    required bool validateLaunch,
  })
  _classify;

  @override
  TerminalObservationBinding bind(
    TerminalObservationBus bus,
    TerminalObservationSeat seat,
  ) {
    final startupOutput = StringBuffer();
    final outputSubscription = bus.addOutputObserver(
      _LaunchStartOutputObserver(startupOutput, _classify),
      phases: {TerminalLaunchPhase.spawning, TerminalLaunchPhase.confirming},
    );
    final exitSubscription = bus.addProcessExitObserver((code) {
      if (seat.phase != TerminalLaunchPhase.spawning &&
          seat.phase != TerminalLaunchPhase.confirming) {
        return;
      }
      String? classified;
      try {
        classified = _classify(
          startupOutput.toString(),
          executable: seat.startupExecutable,
          validateLaunch: seat.validateLaunch,
        );
      } on Object catch (error, stackTrace) {
        AppLogger.instance.e(
          'LaunchStartModule classify failed',
          error: error,
          stackTrace: stackTrace,
          recordError: false,
        );
      }
      seat.failLaunch?.call(
        classified ??
            composeProcessExitFailureMessage(
              code: code,
              recentOutput: startupOutput.toString(),
              duringStartup: true,
            ),
      );
    });
    return CallbackObservationBinding(() {
      outputSubscription.cancel();
      exitSubscription.cancel();
    });
  }
}

final class _LaunchStartOutputObserver implements TerminalOutputObserver {
  _LaunchStartOutputObserver(this._startupOutput, this._classify);

  final StringBuffer _startupOutput;
  final String? Function(
    String text, {
    required String executable,
    required bool validateLaunch,
  })
  _classify;

  @override
  void onOutput(Uint8List bytes, TerminalObservationSeat seat) {
    _startupOutput.write(utf8.decode(bytes, allowMalformed: true));
    final String? classified;
    try {
      classified = _classify(
        _startupOutput.toString(),
        executable: seat.startupExecutable,
        validateLaunch: seat.validateLaunch,
      );
    } on Object catch (error, stackTrace) {
      AppLogger.instance.e(
        'LaunchStartModule classify failed',
        error: error,
        stackTrace: stackTrace,
        recordError: false,
      );
      return;
    }
    if (classified != null) {
      seat.failLaunch?.call(classified);
      return;
    }
    seat.confirmStarted?.call();
  }
}
