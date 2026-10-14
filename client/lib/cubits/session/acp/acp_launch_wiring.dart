import 'dart:async';
import 'dart:convert';

import '../../../models/team_config.dart';
import '../../../services/acp/acp_agent_translator.dart';
import '../../../services/acp/acp_connection.dart';
import '../../../services/acp/acp_frame_logger.dart';
import '../../../services/acp/acp_process_transport.dart';
import '../../../services/acp/acp_session_runtime.dart';
import '../../../services/cli/registry/capabilities/acp_capability.dart';
import '../../../services/cli/registry/cli_tool_registry.dart';
import '../../../utils/logging/logger_utils.dart';

/// Composition root for the production ACP launch path: adapter + spawner.
///
/// Lives at the chat wiring layer (not in `services/acp`) because it needs
/// the [AcpCapability] type from `services/cli/registry` — the established
/// dependency direction there is registry → acp, and the runtime stays
/// CLI-agnostic.

/// Adapts an [AcpCapability] to the runtime's [AcpLaunchPlan] shape.
///
/// Null when the CLI declares no ACP capability (the runtime then throws
/// [ArgumentError]). Tear-off-free because [AcpLaunchPlan]'s
/// `buildEnvironment` typedef has a default value for [baseEnv] that the
/// capability's matching signature satisfies structurally.
Future<String?> spawnAuthenticateMethodId(
  AcpCapability? capability,
  Map<String, String> env,
) async {
  if (capability == null) return null;
  return capability.resolveAuthenticateMethodId(env);
}

bool _looksAbsolute(String value) =>
    value.contains('/') || value.contains(r'\');

AcpLaunchPlan? capabilityToPlan(
  AcpCapability? capability, {
  String? Function()? discoveredAdapterPath,
}) {
  if (capability == null) return null;
  return AcpLaunchPlan(
    launchArgCandidates: capability.launchArgCandidates,
    buildEnvironment:
        ({
          required String sessionToolDir,
          required String workingDirectory,
          Map<String, String> baseEnv = const {},
        }) => capability.buildEnvironment(
          sessionToolDir: sessionToolDir,
          workingDirectory: workingDirectory,
          baseEnv: baseEnv,
        ),
    agentExecutable: (cliExecutable) {
      final discovered = discoveredAdapterPath?.call()?.trim() ?? '';
      if (_looksAbsolute(discovered)) return discovered;
      return capability.agentExecutable(cliExecutable);
    },
    authenticateMethodId: capability.authenticateMethodId,
    forwardSessionNewMcpServers: capability.forwardSessionNewMcpServers,
    sessionNewMeta: capability.sessionNewMeta,
  );
}

/// Resolves the launch plan for [tool] from [registry] (runtime resolver).
AcpLaunchPlanResolver acpLaunchPlanResolver(
  CliToolRegistry registry, {
  String? Function(CliTool tool)? discoveredAdapterPath,
}) {
  return (tool) => capabilityToPlan(
    registry.capability<AcpCapability>(tool),
    discoveredAdapterPath: () => discoveredAdapterPath?.call(tool),
  );
}

/// Builds the production [AcpConnectionSpawner] for one session launch.
///
/// [workingDirectory] and the tool's [AcpAgentTranslator] are captured here
/// (the spawner's signature is argv+env only, per the runtime seam). The
/// spawner runs initialize, then optional authenticate, each raced against
/// process exit and classified by handshake phase:
///
/// - agent exits **during initialize** → [AcpFlagRejected] (unknown/renamed
///   flag; the runtime tries the next candidate);
/// - agent exits **during authenticate** (after initialize succeeded) →
///   [AcpAuthenticateException] (not logged in; do not try another candidate);
/// - everything else (handshake timeout, malformed response, zero exit) →
///   rethrown as a normal error — a timeout must NOT burn another candidate.
AcpConnectionSpawner productionAcpSpawner({
  required CliToolRegistry registry,
  required CliTool tool,
  required String workingDirectory,
  required AcpFrameLogger logger,
  String clientName = 'teampilot',
  String clientVersion = '1.0.0',
  Duration handshakeTimeout = const Duration(seconds: 30),
}) {
  final translator =
      registry.capability<AcpCapability>(tool)?.translator ??
      const _NoopAcpTranslator();
  return (argv, env) async {
    final transport = await AcpProcessTransport.start(
      executable: argv.first,
      args: argv.skip(1).toList(),
      environment: env,
      workingDirectory: workingDirectory,
      onStderr: (chunk) {
        if (chunk.isEmpty) return;
        AppLogger.instance.d(
          '[acp-stderr] ${utf8.decode(chunk, allowMalformed: true)}',
        );
      },
    );
    // Observed by the runtime's agent-exit watcher after a successful start
    // (mid-session crash → inline system message). Futures are multicast, so
    // sharing this with the handshake race below is safe.
    final processExitCode = transport.processExitCode;
    final connection = AcpAgentConnection(
      transport: transport,
      logger: logger,
      translator: translator,
      processExitCode: processExitCode,
    );
    try {
      final authenticateMethodId = await spawnAuthenticateMethodId(
        registry.capability<AcpCapability>(tool),
        env,
      );
      // Initialize race uses authenticating: false — an old CLI dying on
      // the flag is still AcpFlagRejected, not not-logged-in.
      await raceHandshake(
        connection.initialize(
          clientName: clientName,
          clientVersion: clientVersion,
          timeout: handshakeTimeout,
        ),
        processExitCode,
        authenticating: false,
      );
      if (authenticateMethodId != null) {
        // Authenticate race uses authenticating: true — exit after
        // initialize succeeded is not-logged-in, not a bad flag.
        await raceHandshake(
          connection.authenticate(
            authenticateMethodId,
            timeout: handshakeTimeout,
          ),
          processExitCode,
          authenticating: true,
        );
      }
      return connection;
    } on Object {
      await connection.dispose();
      rethrow;
    }
  };
}

/// Fallback translator for tools whose ACP capability is missing (fails
/// loudly upstream anyway; keeps the spawner total).
class _NoopAcpTranslator extends AcpAgentTranslator {
  const _NoopAcpTranslator();

  @override
  List<String> get flagCandidates => const [];

  @override
  List<String> get blockingClientMethods => const [];

  @override
  List<String> get notificationClientMethods => const [];

  @override
  String translateStopError(Object error, {required bool suppressAbort}) {
    AppLogger.instance.w(
      'ACP: translator missing; surfacing raw stop error: $error',
    );
    return error.toString();
  }
}

/// Classifies a process exit that won the handshake race.
///
/// Returns [AcpAuthenticateException], [AcpFlagRejected], or [StateError].
/// [StateError] is an [Error], so the return type cannot be [Exception].
Object classifyHandshakeProcessExit({
  required int exitCode,
  required bool authenticating,
}) {
  if (authenticating) {
    return AcpAuthenticateException(
      'agent process exited with code $exitCode during authenticate',
    );
  }
  if (exitCode != 0) {
    return AcpFlagRejected(
      'agent process exited with code $exitCode '
      'before the ACP handshake completed',
    );
  }
  return StateError(
    'agent process exited cleanly (code 0) before completing the '
    'ACP handshake',
  );
}

/// Races [handshake] against [processExitCode] and classifies a process
/// death by handshake phase.
///
/// [authenticating] is false for the initialize race ([AcpFlagRejected])
/// and true for the authenticate race ([AcpAuthenticateException]).
Future<void> raceHandshake<T>(
  Future<T> handshake,
  Future<int> processExitCode, {
  required bool authenticating,
}) async {
  final winner = await Future.any([
    handshake.then((_) => const _HandshakeDone()),
    processExitCode.then(_ProcessExited.new),
  ]);
  if (winner is _ProcessExited) {
    throw classifyHandshakeProcessExit(
      exitCode: winner.exitCode,
      authenticating: authenticating,
    );
  }
}

final class _HandshakeDone {
  const _HandshakeDone();
}

final class _ProcessExited {
  const _ProcessExited(this.exitCode);
  final int exitCode;
}
