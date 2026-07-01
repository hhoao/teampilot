import 'dart:async';
import 'dart:io';

import 'package:teampilot/services/team/terminal_activity_tracker.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';

import '../../support/recording_pty_transport.dart';

/// [TerminalSession] connected through [RecordingPtyTransport] so integration
/// tests observe real [writeToPty] / [submitFullScreenInput] bytes and can
/// drive [TerminalActivityTracker] via synthetic PTY output.
class ConnectedRecordingShell {
  ConnectedRecordingShell({
    required this.session,
    required this.transport,
  });

  final TerminalSession session;
  final RecordingPtyTransport transport;

  TerminalActivityTracker get activityTracker => session.activityTracker;

  List<String> get ptyInput => transport.decodedWrites;

  bool get isRunning => session.isRunning;
  bool get isConnected => session.isConnected;

  /// All stdin writes joined — doorbell notices contain `[teammate-bus]`.
  String get ptyInputJoined => ptyInput.join();

  Future<void> dispose() async {
    session.dispose();
    await transport.dispose();
  }

  /// Boot the transport and confirm the session (first PTY output or fallback).
  static Future<ConnectedRecordingShell> connect({
    Duration confirmFallback = const Duration(milliseconds: 20),
  }) async {
    final transport = RecordingPtyTransport();
    final session = TerminalSession(
      executable: 'true',
      validateLaunch: false,
      parseExecutable: false,
      confirmFallback: confirmFallback,
      transportStarter:
          (
            executable, {
            required arguments,
            required workingDirectory,
            required columns,
            required rows,
            environment,
          }) {
            return Future.value(transport);
          },
    );
    session.connect(workingDirectory: Directory.systemTemp.path);
    session.onViewportResize(80, 24);
    transport.emitUtf8('ready\r\n');
    await Future<void>.delayed(Duration.zero);
    return ConnectedRecordingShell(session: session, transport: transport);
  }

  /// PTY bytes → [_feedPtyBytes] → [activityTracker.markActive] when connected.
  Future<void> emitPtyOutput(String text) async {
    transport.emitUtf8(text);
    await Future<void>.delayed(Duration.zero);
  }

  /// Past [TerminalActivityTracker.idleAfter] with no new output.
  void simulateQuietGap({Duration ago = const Duration(seconds: 5)}) {
    activityTracker.markActive(DateTime.now().subtract(ago));
  }
}