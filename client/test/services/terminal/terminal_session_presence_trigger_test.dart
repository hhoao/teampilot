import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/event/agent_presence_event.dart';
import 'package:teampilot/services/team/terminal_activity_tracker.dart';
import 'package:teampilot/services/terminal/terminal_launch_controller.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';
import 'package:teampilot/services/terminal/terminal_transport.dart';

import '../../support/in_memory_filesystem.dart';
import '../../support/rust_lib_test_init.dart';

/// Minimal transport double: never spawns, ignores writes.
class _FakeTransport implements TerminalTransport {
  final outputController = StreamController<Uint8List>();
  final doneCompleter = Completer<int>();

  @override
  Stream<Uint8List> get output => outputController.stream;

  @override
  Future<int> get done => doneCompleter.future;

  @override
  int? get pid => null;

  @override
  void close() {
    if (!doneCompleter.isCompleted) doneCompleter.complete(0);
  }

  @override
  void resize(int rows, int columns) {}

  @override
  void write(Uint8List data) {}
}

void main() {
  setUpAll(initRustLibForTests);

  /// Session wired to a fresh fake transport per connect, reporting presence
  /// refresh requests through [onPresenceInputsChanged].
  TerminalSession connectable({
    required void Function() onPresenceInputsChanged,
  }) {
    return TerminalSession(
      executable: 'unused',
      validateLaunch: false,
      parseExecutable: false,
      confirmFallback: const Duration(milliseconds: 10),
      transportStarter:
          (
            executable, {
            required arguments,
            required workingDirectory,
            required columns,
            required rows,
            environment,
          }) => Future.value(_FakeTransport()),
      fs: InMemoryFilesystem(),
      onPresenceInputsChanged: onPresenceInputsChanged,
    );
  }

  Future<void> waitFor(bool Function() condition) async {
    for (var i = 0; i < 200; i++) {
      if (condition()) return;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    fail('condition not met within timeout');
  }

  test('turn latch transitions request a presence refresh', () {
    var calls = 0;
    final s = TerminalSession(
      executable: 'unused',
      validateLaunch: false,
      parseExecutable: false,
      fs: InMemoryFilesystem(),
      onPresenceInputsChanged: () => calls++,
    );
    addTearDown(s.dispose);
    s.markUserTurnStarted();
    s.markUserTurnIdle();
    expect(calls, 2);
  });

  test('presenceSeat is null until an observation binds an identity', () {
    final s = TerminalSession(
      executable: 'unused',
      validateLaunch: false,
      parseExecutable: false,
      fs: InMemoryFilesystem(),
    );
    addTearDown(s.dispose);
    expect(s.presenceSeat, isNull);
  });

  test('self-created tracker pushes a refresh on the boot latch', () {
    var calls = 0;
    final s = TerminalSession(
      executable: 'unused',
      validateLaunch: false,
      parseExecutable: false,
      fs: InMemoryFilesystem(),
      onPresenceInputsChanged: () => calls++,
    );
    addTearDown(s.dispose);

    s.activityTracker.latchBootFrameReadyForTest();
    s.activityTracker.notePtyBytes(Uint8List.fromList([0x41, 0x0a]));

    expect(calls, 1);
  });

  test('injected tracker keeps its own listener; session does not hijack', () {
    final injected = TerminalActivityTracker();
    var injectedCalls = 0;
    injected.setBootFrameListener((_) => injectedCalls++);
    var sessionCalls = 0;
    final s = TerminalSession(
      executable: 'unused',
      validateLaunch: false,
      parseExecutable: false,
      launchController: TerminalLaunchController(
        engine: TerminalEngine(config: TerminalConfig.defaults()),
        activityTracker: injected,
        defaultExecutable: 'unused',
        startupDeadline: const Duration(seconds: 5),
        confirmFallback: const Duration(milliseconds: 50),
        validateLaunch: false,
      ),
      fs: InMemoryFilesystem(),
      onPresenceInputsChanged: () => sessionCalls++,
    );
    addTearDown(s.dispose);

    expect(s.activityTracker, same(injected));

    injected.latchBootFrameReadyForTest();
    injected.notePtyBytes(Uint8List.fromList([0x41, 0x0a]));

    expect(injectedCalls, 1, reason: 'owner listener must stay intact');
    expect(sessionCalls, 0, reason: 'session must not adopt a foreign tracker');
  });

  test('presenceSeat binds identity and rebind revives the boot push', () async {
    var calls = 0;
    final s = connectable(onPresenceInputsChanged: () => calls++);
    addTearDown(s.dispose);

    s.connect(
      workingDirectory: Directory.systemTemp.path,
      observation: const TerminalObservationAttach(
        sessionId: 's1',
        memberId: 'm1',
      ),
    );
    await waitFor(() => s.isConnected);
    expect(
      s.presenceSeat,
      const PresenceSeatKey(sessionId: 's1', memberId: 'm1'),
    );

    s.activityTracker.latchBootFrameReadyForTest();
    s.activityTracker.notePtyBytes(Uint8List.fromList([0x41, 0x0a]));
    expect(calls, 1, reason: 'boot latch pushes while bound');

    s.disconnect();
    expect(s.presenceSeat, isNull, reason: 'unbind clears the seat');

    s.connect(
      workingDirectory: Directory.systemTemp.path,
      observation: const TerminalObservationAttach(
        sessionId: 's1',
        memberId: 'm1',
      ),
    );
    await waitFor(() => s.isConnected);
    expect(
      s.presenceSeat,
      const PresenceSeatKey(sessionId: 's1', memberId: 'm1'),
    );

    s.activityTracker.latchBootFrameReadyForTest();
    s.activityTracker.notePtyBytes(Uint8List.fromList([0x42, 0x0a]));
    expect(calls, 2, reason: 'rebind must re-attach the boot push');
  });

  test('an observation without identity leaves presenceSeat null', () async {
    var calls = 0;
    final s = connectable(onPresenceInputsChanged: () => calls++);
    addTearDown(s.dispose);

    s.connect(workingDirectory: Directory.systemTemp.path);
    await waitFor(() => s.isConnected);
    expect(s.presenceSeat, isNull);
  });
}
