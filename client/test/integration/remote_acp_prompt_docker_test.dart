@Tags(['integration', 'docker'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/session/acp/acp_launch_wiring.dart';
import 'package:teampilot/cubits/session/acp/acp_transport_wiring.dart';
import 'package:teampilot/models/cli_binary_kind.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/ssh_known_host_repository.dart';
import 'package:teampilot/services/acp/acp_frame_logger.dart';
import 'package:teampilot/services/acp/acp_session.dart';
import 'package:teampilot/services/acp/acp_session_runtime.dart';
import 'package:teampilot/services/acp/acp_ssh_transport.dart';
import 'package:teampilot/services/cli/claude/capabilities/acp.dart';
import 'package:teampilot/services/cli/claude/claude_tool.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/remote/remote_cli_readiness.dart';
import 'package:teampilot/services/ssh/ssh_client_factory.dart';

import 'support/docker_ssh_server.dart';

/// End-to-end **remote ACP prompt over real SSH + Docker** for Claude Code.
///
/// Unlike `remote_acp_adapter_docker_test.dart` (locate → install → spawn), this
/// test drives a full turn through the production seams:
/// docker sshd → `claude-agent-acp` (real adapter) → ACP `initialize` /
/// `session/new` / `session/prompt` → assistant `session/update` → stop.
///
/// The model backend is a local Anthropic-compatible stub on the host, reached
/// by the container through `host.docker.internal`. That keeps the test
/// hermetic (no API key / OAuth available in CI) while still exercising the
/// real adapter, the real ACP protocol, and the real SSH exec transport. The
/// measured latency therefore excludes upstream model time.
///
/// Run from `client/` (needs Docker + outbound network for the npm adapter
/// install; the mixed image already bakes Node + `claude`):
/// ```bash
/// dart run tool/run_tests.dart --tags "integration && docker" \
///   test/integration/remote_acp_prompt_docker_test.dart
/// ```
void main() {
  // Covers everything the user waits for, including the container start.
  final totalWatch = Stopwatch()..start();
  var dockerStartMs = 0;
  DockerSshServer? server;
  SshClientFactory? sshFactory;
  _AnthropicStub? stub;
  final cliOverrides = <String, String>{};
  final adapterOverrides = <String, String>{};

  setUpAll(() async {
    if (!await DockerSshServer.isDockerAvailable()) {
      return;
    }
    stub = await _AnthropicStub.start();
    final dockerWatch = Stopwatch()..start();
    server = await DockerSshServer.startMixed(clientRoot: Directory.current.path);
    dockerStartMs = dockerWatch.elapsedMilliseconds;

    final credentials = InMemorySshCredentialStore();
    await credentials.savePassword(
      _profileId,
      DockerSshServer.defaultPassword,
    );
    sshFactory = SshClientFactory(
      credentialStore: credentials,
      knownHostRepository: InMemorySshKnownHostRepository(),
      onHostKeyPrompt: (_) async => true,
    );
  });

  tearDownAll(() async {
    sshFactory?.disconnectAll();
    await server?.stop();
    await stub?.stop();
  });

  test('remote Claude ACP prompt round trip over Docker SSH', () async {
    if (server == null || sshFactory == null || stub == null) {
      markTestSkipped('Docker is not available');
    }
    final docker = server!;
    final factory = sshFactory!;
    final anthropic = stub!;
    final total = Stopwatch()..start();

    final profile = _profile.copyWith(port: docker.port);
    final target = RuntimeTarget(
      id: 'ssh:${profile.id}',
      label: profile.name,
      kind: RuntimeKind.ssh,
      sshProfileId: profile.id,
    );

    final readiness = RemoteCliReadinessService(
      registry: CliToolRegistry.builtIn(),
      sshClientFactory: factory,
      profileById: (id) => id == profile.id ? profile : null,
      cliPathOverride: (t, c) async => cliOverrides['$t|$c'],
      setCliPathOverride: (t, c, p) async => cliOverrides['$t|$c'] = p,
      acpAdapterPathOverride: (t, c) async => adapterOverrides['$t|$c'],
      setAcpAdapterPathOverride: (t, c, p) async => adapterOverrides['$t|$c'] = p,
    );

    // 1. Reuse the adapter when a previous run already installed it.
    final installWatch = Stopwatch()..start();
    var adapter = await readiness.probe(
      target: target,
      cli: CliTool.claude,
      kind: CliBinaryKind.adapter,
    );
    var adapterInstalledHere = false;
    if (adapter is! RemoteCliReady) {
      adapterInstalledHere = true;
      adapter = await readiness.install(
        target: target,
        cli: CliTool.claude,
        kind: CliBinaryKind.adapter,
      );
    }
    installWatch.stop();
    expect(
      adapter,
      isA<RemoteCliReady>(),
      reason: adapter is RemoteCliFailed ? adapter.message : null,
    );

    // 2. Real SSH exec channel (production transport seam). Reconnect after the
    //    readiness service's pooled client so the connect cost is measured for
    //    the launch itself, not attributed to the adapter install.
    factory.disconnectAll();
    final sshWatch = Stopwatch()..start();
    final sshClient = await factory.clientForStorage(
      profile,
      timeout: const Duration(seconds: 30),
    );
    sshWatch.stop();

    final registry = CliToolRegistry()
      ..register(
        ClaudeCliTool(
          acp: ClaudeAcpCapability(
            // Stub backend: an API key makes the adapter pick API-key mode
            // instead of looking for an Official OAuth login in the container.
            authSource: () => ClaudeAcpAuth(
              apiKey: _stubApiKey,
              baseUrl: anthropic.baseUrl,
            ),
          ),
        ),
      );
    final logger = AcpFrameLogger(mirrorToLog: false);
    final runtime = AcpSessionRuntime(
      spawner: productionAcpSpawner(
        registry: registry,
        tool: CliTool.claude,
        workingDirectory: _remoteWorkingDirectory,
        logger: logger,
        transportStarter: sshAcpTransportStarter(
          profile: profile,
          openChannel: (command) async =>
              DartSsh2AcpChannel(await sshClient.execute(command)),
        ),
        handshakeTimeout: const Duration(seconds: 90),
      ),
      logger: logger,
      launchPlanFor: acpLaunchPlanResolver(registry),
    );

    var closeWatch = Stopwatch()..start();
    try {
      // 3. Spawn `claude-agent-acp` on the remote host and complete the ACP
      //    handshake (`initialize` + `session/new`).
      final handshakeWatch = Stopwatch()..start();
      await runtime.start(
        tool: CliTool.claude,
        executable: ClaudeAcpCapability.adapterName,
        sessionToolDir: _remoteConfigDir,
        workingDirectory: _remoteWorkingDirectory,
        baseEnv: const {
          'CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC': '1',
          'DISABLE_AUTOUPDATER': '1',
        },
      );
      handshakeWatch.stop();

      // 4. Send one prompt and wait for the assistant reply.
      final reply = StringBuffer();
      final firstChunk = Completer<void>();
      final updates = runtime.updates.listen((update) {
        if (update is AcpMessageChunk && update.role == AcpRole.assistant) {
          reply.write(update.content);
          if (!firstChunk.isCompleted) firstChunk.complete();
        }
      });

      final promptWatch = Stopwatch()..start();
      await runtime.prompt(_promptText);
      await firstChunk.future.timeout(const Duration(seconds: 30));
      promptWatch.stop();
      await updates.cancel();

      expect(reply.toString(), contains('PONG'));
      expect(
        anthropic.requestBodies.any((body) => body.contains(_promptText)),
        isTrue,
        reason: 'the stub backend never received the prompt',
      );

      closeWatch = Stopwatch()..start();
      total.stop();
      totalWatch.stop();
      // ignore: avoid_print
      print(
        '[acp-docker] docker_start_ms=$dockerStartMs '
        'adapter_install_ms=${installWatch.elapsedMilliseconds} '
        '(installed_here=$adapterInstalledHere) '
        'ssh_connect_ms=${sshWatch.elapsedMilliseconds} '
        'acp_handshake_ms=${handshakeWatch.elapsedMilliseconds} '
        'prompt_round_trip_ms=${promptWatch.elapsedMilliseconds} '
        'total_before_close_ms=${total.elapsedMilliseconds} '
        'test_total_ms=${totalWatch.elapsedMilliseconds} '
        'adapter=${(adapter as RemoteCliReady).path}',
      );
    } finally {
      await runtime.close();
      closeWatch.stop();
      // ignore: avoid_print
      print('[acp-docker] close_ms=${closeWatch.elapsedMilliseconds}');
    }
  }, timeout: const Timeout(Duration(minutes: 15)));
}

const _profileId = 'docker-acp-prompt-it';
const _stubApiKey = 'sk-ant-teampilot-it-stub';
const _promptText = 'Reply with exactly PONG';
const _remoteWorkingDirectory = '/home/${DockerSshServer.defaultUsername}';
const _remoteConfigDir = '/tmp/teampilot-acp-prompt-it/claude';

const _profile = SshProfile(
  id: _profileId,
  name: 'docker-acp-prompt-it',
  host: '127.0.0.1',
  port: 22,
  username: DockerSshServer.defaultUsername,
);

/// Minimal Anthropic Messages API stub for the Claude Code adapter.
///
/// Handles both the streaming POST (`text/event-stream`) and the SDK's
/// non-streaming retry, plus `/count_tokens`. Every request body is recorded so
/// the test can prove the prompt reached the "model".
class _AnthropicStub {
  _AnthropicStub._(this._server);

  final HttpServer _server;
  final List<String> requestBodies = [];

  String get baseUrl => 'http://host.docker.internal:${_server.port}';

  static Future<_AnthropicStub> start() async {
    final server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    final stub = _AnthropicStub._(server);
    server.listen(
      stub._handle,
      onError: (Object _) {},
      cancelOnError: false,
    );
    return stub;
  }

  Future<void> _handle(HttpRequest request) async {
    final body = await utf8.decoder.bind(request).join();
    requestBodies.add(body);
    final path = request.uri.path;
    final response = request.response;
    response.headers.set('request-id', 'req_stub_1');

    if (path.endsWith('/count_tokens')) {
      response.headers.contentType = ContentType.json;
      response.write(jsonEncode({'input_tokens': 12}));
      await response.close();
      return;
    }
    if (path.endsWith('/messages')) {
      final payload = _decode(body);
      final streaming = payload['stream'] != false;
      if (streaming) {
        response.headers.contentType = ContentType(
          'text',
          'event-stream',
          charset: 'utf-8',
        );
        response.write(_sseEvents());
      } else {
        response.headers.contentType = ContentType.json;
        response.write(jsonEncode(_message(payload)));
      }
      await response.close();
      return;
    }

    response.statusCode = HttpStatus.notFound;
    await response.close();
  }

  Map<String, Object?> _decode(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, Object?> ? decoded : const {};
    } on FormatException {
      return const {};
    }
  }

  String _sseEvents() {
    final events = <(String, Map<String, Object?>)>[
      (
        'message_start',
        {
          'type': 'message_start',
          'message': _message(const {}, streamingStart: true),
        },
      ),
      (
        'content_block_start',
        {
          'type': 'content_block_start',
          'index': 0,
          'content_block': {'type': 'text', 'text': ''},
        },
      ),
      (
        'content_block_delta',
        {
          'type': 'content_block_delta',
          'index': 0,
          'delta': {'type': 'text_delta', 'text': 'PONG'},
        },
      ),
      (
        'content_block_stop',
        {'type': 'content_block_stop', 'index': 0},
      ),
      (
        'message_delta',
        {
          'type': 'message_delta',
          'delta': {'stop_reason': 'end_turn', 'stop_sequence': null},
          'usage': {'output_tokens': 1},
        },
      ),
      ('message_stop', {'type': 'message_stop'}),
    ];
    return events
        .map((event) => 'event: ${event.$1}\ndata: ${jsonEncode(event.$2)}\n\n')
        .join();
  }

  Map<String, Object?> _message(
    Map<String, Object?> payload, {
    bool streamingStart = false,
  }) {
    return {
      'id': 'msg_stub_1',
      'type': 'message',
      'role': 'assistant',
      'model': payload['model'] ?? 'claude-stub',
      'content': streamingStart
          ? const <Object?>[]
          : const [
              {'type': 'text', 'text': 'PONG'},
            ],
      'stop_reason': streamingStart ? null : 'end_turn',
      'stop_sequence': null,
      'usage': {'input_tokens': 12, 'output_tokens': streamingStart ? 0 : 1},
    };
  }

  Future<void> stop() => _server.close(force: true);
}
