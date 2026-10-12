import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/session/acp/acp_launch_wiring.dart';
import 'package:teampilot/services/acp/acp_session_runtime.dart';

void main() {
  test(
    'process exit during authenticate is AcpAuthenticateException, not a flag reject',
    () {
      final error = classifyHandshakeProcessExit(
        exitCode: 1,
        authenticating: true,
      );
      expect(error, isA<AcpAuthenticateException>());
    },
  );

  test(
    'non-zero exit before handshake without authenticate is AcpFlagRejected',
    () {
      final error = classifyHandshakeProcessExit(
        exitCode: 1,
        authenticating: false,
      );
      expect(error, isA<AcpFlagRejected>());
    },
  );

  test('clean exit before handshake is StateError', () {
    final error = classifyHandshakeProcessExit(
      exitCode: 0,
      authenticating: false,
    );
    expect(error, isA<StateError>());
  });

  test('raceHandshake: handshake completes first → ok', () async {
    final handshake = Completer<void>();
    final exit = Completer<int>();
    final raced = raceHandshake(
      handshake.future,
      exit.future,
      authenticating: false,
    );
    handshake.complete();
    await expectLater(raced, completes);
  });

  test(
    'raceHandshake: exit 1 before handshake, authenticating false → AcpFlagRejected',
    () async {
      final handshake = Completer<void>();
      final exit = Completer<int>();
      final raced = raceHandshake(
        handshake.future,
        exit.future,
        authenticating: false,
      );
      exit.complete(1);
      await expectLater(raced, throwsA(isA<AcpFlagRejected>()));
    },
  );

  test(
    'raceHandshake: exit 1 before handshake, authenticating true → AcpAuthenticateException',
    () async {
      final handshake = Completer<void>();
      final exit = Completer<int>();
      final raced = raceHandshake(
        handshake.future,
        exit.future,
        authenticating: true,
      );
      exit.complete(1);
      await expectLater(raced, throwsA(isA<AcpAuthenticateException>()));
    },
  );
}
