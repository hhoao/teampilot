import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/session/acp/acp_launch_wiring.dart';
import 'package:teampilot/services/acp/acp_agent_translator.dart';
import 'package:teampilot/services/acp/acp_session_runtime.dart';
import 'package:teampilot/services/cli/registry/capabilities/acp_capability.dart';

class _FixedAuthCapability implements AcpCapability {
  _FixedAuthCapability(this.authenticateMethodId, {this.resolved});

  @override
  final String? authenticateMethodId;
  final String? resolved;

  @override
  bool get forwardSessionNewMcpServers => true;

  @override
  Future<String?> resolveAuthenticateMethodId(Map<String, String> env) async {
    if (env['FORCE_SKIP'] == '1') return null;
    return resolved ?? authenticateMethodId;
  }

  @override
  String agentExecutable(String cliExecutable) => cliExecutable;

  @override
  List<List<String>> launchArgCandidates(String executable) => [
    [executable],
  ];

  @override
  AcpAgentTranslator get translator => const _NoopTranslator();

  @override
  Map<String, String> buildEnvironment({
    required String sessionToolDir,
    required String workingDirectory,
    Map<String, String> baseEnv = const {},
  }) => Map<String, String>.of(baseEnv);
}

class _NoopTranslator extends AcpAgentTranslator {
  const _NoopTranslator();
  @override
  List<String> get flagCandidates => const [];
  @override
  List<String> get blockingClientMethods => const [];
  @override
  List<String> get notificationClientMethods => const [];
  @override
  String translateStopError(Object error, {required bool suppressAbort}) =>
      error.toString();
}

void main() {
  test(
    'spawnAuthenticateMethodId uses resolver not the declared getter',
    () async {
      final cap = _FixedAuthCapability('cursor_login');
      expect(await spawnAuthenticateMethodId(cap, {'FORCE_SKIP': '1'}), isNull);
      expect(await spawnAuthenticateMethodId(cap, const {}), 'cursor_login');
      expect(await spawnAuthenticateMethodId(null, const {}), isNull);
    },
  );

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
