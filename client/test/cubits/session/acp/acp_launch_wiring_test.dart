import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:acpd/acpd.dart' as acpd;
import 'package:acpd_test/acpd_test.dart' as acpd_test;
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/session/acp/acp_launch_wiring.dart';
import 'package:teampilot/cubits/session/acp/acp_transport_wiring.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/acp/acp_agent_translator.dart';
import 'package:teampilot/services/acp/acp_frame_logger.dart';
import 'package:teampilot/services/acp/acp_proxy_forward_transport.dart';
import 'package:teampilot/services/acp/acp_session_runtime.dart';
import 'package:teampilot/services/acp/acp_transport.dart';
import 'package:teampilot/services/cli/registry/capabilities/acp_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/ssh/ssh_forward_channel.dart';

class _FixedAuthCapability implements AcpCapability {
  _FixedAuthCapability(this.authenticateMethodId, {this.resolved});

  @override
  final String? authenticateMethodId;
  final String? resolved;

  @override
  Duration get startupTimeout => const Duration(seconds: 30);

  @override
  bool get forwardSessionNewMcpServers => true;

  @override
  bool get supportsInPlaceSessionLoad => true;

  @override
  Map<String, String> get agentStatusEnvironment => const {};

  @override
  Map<String, Object?> sessionNewMeta(Map<String, String> env) => const {};

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

class _SilentTransport implements AcpTransport {
  final _input = StreamController<Uint8List>.broadcast();
  @override
  Stream<Uint8List> get input => _input.stream;
  @override
  void write(String frame) {}
  @override
  Stream<List<int>> get stderr => const Stream.empty();
  @override
  Future<void> close() async {
    if (!_input.isClosed) await _input.close();
  }

  @override
  bool get isClosed => _input.isClosed;
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

  test('capabilityToPlan prefers an absolute discovered adapter path', () {
    final plan = capabilityToPlan(
      _FixedAuthCapability(null),
      discoveredAdapterPath: () => '/opt/claude-agent-acp',
    )!;
    expect(plan.agentExecutable('/usr/bin/claude'), '/opt/claude-agent-acp');
  });

  test('capabilityToPlan ignores a bare discovered name', () {
    final plan = capabilityToPlan(
      _FixedAuthCapability(null),
      discoveredAdapterPath: () => 'claude-agent-acp',
    )!;
    expect(plan.agentExecutable('/usr/bin/claude'), '/usr/bin/claude');
  });

  test(
    'productionAcpSpawner uses the injected starter and classifies its exit',
    () async {
      List<String>? seenArgv;
      String? seenWorkingDirectory;
      final exit = Completer<int>();
      Future<AcpStartedTransport> starter({
        required List<String> argv,
        required Map<String, String> env,
        required String workingDirectory,
        void Function(List<int>)? onStderr,
      }) async {
        seenArgv = argv;
        seenWorkingDirectory = workingDirectory;
        return (
          transport: _SilentTransport(),
          processExitCode: exit.future,
          pid: null,
        );
      }

      final spawner = productionAcpSpawner(
        registry: CliToolRegistry.builtIn(),
        tool: CliTool.opencode,
        workingDirectory: '/remote/work',
        logger: AcpFrameLogger(),
        transportStarter: starter,
        handshakeTimeout: const Duration(milliseconds: 200),
      );

      final launched = spawner(['opencode', 'acp'], const {});
      exit.complete(127);
      await expectLater(launched, throwsA(isA<AcpFlagRejected>()));
      expect(seenArgv, ['opencode', 'acp']);
      expect(seenWorkingDirectory, '/remote/work');
    },
  );

  test('a proxy forward skips authenticate and carries cursor_login', () async {
    final agent = acpd_test.MockAgent();
    final methods = <String>[];
    agent.connection.onRequest('initialize', (params) {
      methods.add('initialize');
      return acpd.InitializeResponse(
        protocolVersion: acpd.ProtocolVersion.v1,
      ).toJson();
    });
    agent.connection.onRequest('authenticate', (params) {
      methods.add('authenticate');
      return <String, Object?>{};
    });
    final bridge = _AgentBridge(agent.clientTransport);
    addTearDown(() async {
      await bridge.close();
      await agent.close();
    });

    final spawner = productionAcpSpawner(
      registry: CliToolRegistry.builtIn(),
      tool: CliTool.cursor,
      workingDirectory: '/remote/work',
      logger: AcpFrameLogger(mirrorToLog: false),
      transportStarter:
          ({
            required argv,
            required env,
            required workingDirectory,
            onStderr,
          }) async {
            return (
              transport: AcpProxyForwardTransport(
                channel: bridge,
                argv: argv,
                env: env,
              ),
              processExitCode: null,
              pid: null,
            );
          },
    );

    final connection = await spawner(const ['agent', 'acp'], const {});
    addTearDown(connection.dispose);

    expect(methods, ['initialize']);
    expect(connection.acpProxyLaunch?.authenticateMethodId, 'cursor_login');
    expect(connection.acpProxyLaunch?.argv, const ['agent', 'acp']);
  });
}

class _AgentBridge implements SshForwardByteChannel {
  _AgentBridge(this._peer) {
    _subscription = _peer.incoming.listen((frame) {
      _incoming.add(utf8.encode(frame.toLine()));
    });
  }

  final acpd.Transport _peer;
  final _incoming = StreamController<List<int>>.broadcast();
  late final StreamSubscription<acpd.TransportFrame> _subscription;
  var _buffer = '';
  var _closed = false;

  @override
  Stream<List<int>> get incoming => _incoming.stream;

  @override
  void add(List<int> data) {
    _buffer += utf8.decode(data);
    while (true) {
      final newline = _buffer.indexOf('\n');
      if (newline < 0) return;
      final line = _buffer.substring(0, newline);
      _buffer = _buffer.substring(newline + 1);
      if (line.isEmpty) continue;
      _peer.send(acpd.TransportFrame.decode(line));
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _subscription.cancel();
    if (!_incoming.isClosed) await _incoming.close();
  }
}
