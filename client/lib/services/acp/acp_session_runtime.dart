import 'dart:async';
import 'dart:io';

import '../../models/team_config.dart';
import '../../utils/logging/logger_utils.dart';
import '../agent_status/agent_permission_request.dart';
import 'acp_connection.dart';
import 'acp_frame_logger.dart';
import 'acp_session.dart';

/// l10n key surfaced when no ACP flag candidate produced a usable agent.
///
/// The runtime stays l10n-free; the UI layer resolves this key for the
/// user-facing message.
const String acpLaunchFailedVersion = 'acpLaunchFailedVersion';

/// l10n key surfaced when a separate ACP adapter binary (one whose
/// `agentExecutable` differs from the CLI executable, e.g. Claude's
/// `claude-agent-acp`) is not installed.
const String acpLaunchFailedAdapter = 'acpLaunchFailedAdapter';

/// Creates the [AcpAgentConnection] for one full agent argv + environment.
///
/// Production wires this to [AcpProcessTransport.start] plus the
/// initialize handshake; tests inject a fake returning an in-memory
/// connection (no process).
typedef AcpConnectionSpawner =
    Future<AcpAgentConnection> Function(
      List<String> argv,
      Map<String, String> env,
    );

/// Resolves the ACP launch declaration for [tool], or null when the CLI
/// declares none (then [AcpSessionRuntime.start] throws [ArgumentError]).
///
/// Injected instead of importing `services/cli/registry` from here — the
/// registry's AcpCapability already imports `services/acp`, so a reverse
/// import would be a cycle. Production passes
/// `CliToolRegistry.builtIn().capability<AcpCapability>`.
typedef AcpLaunchPlanResolver = AcpLaunchPlan? Function(CliTool tool);

/// The per-CLI ACP launch declaration the runtime needs to spawn the agent.
///
/// Extracted from [services.cli.registry.capabilities.AcpCapability] (which
/// this layer cannot import without a cycle) by the [AcpLaunchPlanResolver].
class AcpLaunchPlan {
  const AcpLaunchPlan({
    required this.launchArgCandidates,
    required this.buildEnvironment,
    required this.agentExecutable,
  });

  /// Full argv candidates (executable + one ACP flag each), probe order.
  final List<List<String>> Function(String executable) launchArgCandidates;

  /// Env for the agent process (base + isolated config dir + credentials).
  final Map<String, String> Function({
    required String sessionToolDir,
    required String workingDirectory,
    Map<String, String> baseEnv,
  })
  buildEnvironment;

  /// Binary that speaks ACP on stdio, mapped from the CLI executable.
  final String Function(String cliExecutable) agentExecutable;
}

/// The spawner reported that the candidate flag was rejected: the agent
/// process exited (or errored) before the ACP handshake completed — the
/// signature of an unknown/renamed flag. Only this failure moves the runtime
/// on to the next candidate; anything else is a real error and is rethrown.
class AcpFlagRejected implements Exception {
  AcpFlagRejected(this.message);

  final String message;

  @override
  String toString() => 'AcpFlagRejected: $message';
}

/// Thrown by [AcpSessionRuntime.start] when every ACP flag candidate failed.
///
/// [reason] carries the l10n key [acpLaunchFailedVersion]; the UI layer
/// resolves it for display.
class AcpLaunchException implements Exception {
  AcpLaunchException({required this.reason});

  final String reason;

  @override
  String toString() => 'AcpLaunchException: $reason';
}

/// The runtime surface the chat layer consumes.
///
/// Extracted from [AcpSessionRuntime] so the chat cubit and its tests can
/// depend on the seam (all-stub fakes) instead of the concrete process-backed
/// runtime.
abstract interface class AcpSessionRuntimeApi {
  /// Whether [start] has produced a live session.
  bool get isStarted;

  /// The id of the open ACP session.
  String get sessionId;

  /// Spawns the agent process and opens the ACP session.
  Future<void> start({
    required CliTool tool,
    required String executable,
    required String sessionToolDir,
    required String workingDirectory,
    Map<String, String> baseEnv = const {},
  });

  /// Sends one prompt turn; resolves once the turn's stop event is emitted.
  Future<void> prompt(String text);

  /// Turn events for the open session.
  Stream<AcpSessionUpdate> get updates;

  /// Permission cards surfaced by the agent during the open session.
  Stream<AgentPermissionRequest> get permissionRequests;

  /// The live session's agent-process exit code, if observable.
  ///
  /// Never completes for non-process-backed spawn connections (tests /
  /// in-memory transports); callers must not await it unguarded.
  Future<int>? get agentProcessExitCode;

  /// Answers the currently held permission request (if any).
  Future<AgentPermissionReplyKind?> answerPermission(
    AgentPermissionReplyKind reply, {
    AgentPermissionAlwaysOption? always,
  });

  /// Cancels the current prompt turn.
  void cancel();

  /// Disposes the open session (if any) and the agent connection (if any).
  Future<void> close();
}

/// Owns one ACP agent session for the chat layer: spawn + flag probe +
/// session lifecycle.
///
/// [start] probes each flag candidate from the tool's launch plan in order —
/// a candidate whose process dies before the handshake completes (see
/// [AcpFlagRejected]) is skipped, any other failure is rethrown, and
/// exhaustion throws [AcpLaunchException]. On success the runtime holds the
/// single open session and delegates [prompt]/[updates]/
/// [permissionRequests]/[answerPermission]/[cancel] to it; [close] disposes
/// both the session and the connection.
class AcpSessionRuntime implements AcpSessionRuntimeApi {
  AcpSessionRuntime({
    required AcpConnectionSpawner spawner,
    required this.logger,
    AcpLaunchPlanResolver? launchPlanFor,
  }) : _spawner = spawner,
       _launchPlanFor = launchPlanFor ?? _unsupportedLaunchPlan;

  final AcpConnectionSpawner _spawner;
  final AcpLaunchPlanResolver _launchPlanFor;

  /// Ring-buffered protocol diagnostics for the launched agent.
  final AcpFrameLogger logger;

  AcpAgentConnection? _connection;
  AcpAgentSession? _session;

  static AcpLaunchPlan? _unsupportedLaunchPlan(CliTool tool) => null;

  /// `Process.start` executable-not-found (ENOENT / ERROR_FILE_NOT_FOUND)
  /// or a [PathNotFoundException].
  static bool _isMissingExecutable(Object error) {
    if (error is PathNotFoundException) return true;
    return error is ProcessException && error.errorCode == 2;
  }

  /// Whether [start] has produced a live session.
  @override
  bool get isStarted => _session != null;

  /// Spawns the agent process and opens the ACP session.
  ///
  /// Resolves the launch plan for [tool] (throws [ArgumentError] when the CLI
  /// declares no ACP capability), builds the agent environment, probes the
  /// flag candidates in order, and opens the session with
  /// `cwd = workingDirectory`. Throws [StateError] when a session is already
  /// open — this runtime is one-shot; [close] first.
  @override
  Future<void> start({
    required CliTool tool,
    required String executable,
    required String sessionToolDir,
    required String workingDirectory,
    Map<String, String> baseEnv = const {},
  }) async {
    if (_session != null) {
      throw StateError(
        'AcpSessionRuntime already has an open session; close it first.',
      );
    }
    final plan = _launchPlanFor(tool);
    if (plan == null) {
      throw ArgumentError.value(tool, 'tool', 'has no ACP capability');
    }
    final env = plan.buildEnvironment(
      sessionToolDir: sessionToolDir,
      workingDirectory: workingDirectory,
      baseEnv: baseEnv,
    );

    final agent = plan.agentExecutable(executable);
    for (final argv in plan.launchArgCandidates(agent)) {
      AcpAgentConnection? connection;
      try {
        connection = await _spawner(argv, env);
        final session = await connection.openSession(cwd: workingDirectory);
        _connection = connection;
        _session = session;
        return;
      } on AcpFlagRejected catch (error) {
        AppLogger.instance.w(
          'ACP: flag candidate rejected ($argv): $error; trying next',
        );
        await connection?.dispose();
      } on Object catch (error) {
        // A real failure (not a flag rejection): dispose the spawned
        // connection so the process is not left running, then rethrow.
        await connection?.dispose();
        // A separate adapter binary that is not installed gets its own
        // user-actionable key; a missing CLI itself (agent == executable)
        // stays a generic launch failure. Never falls back to a PTY.
        if (agent != executable && _isMissingExecutable(error)) {
          throw AcpLaunchException(reason: acpLaunchFailedAdapter);
        }
        rethrow;
      }
    }
    throw AcpLaunchException(reason: acpLaunchFailedVersion);
  }

  /// The id of the open ACP session (throws [StateError] before [start]).
  @override
  String get sessionId => _session!.sessionId;

  /// Sends one prompt turn; resolves once the turn's stop event is emitted.
  @override
  Future<void> prompt(String text) => _session!.prompt(text);

  /// Turn events for the open session.
  @override
  Stream<AcpSessionUpdate> get updates {
    final session = _session;
    if (session == null) {
      throw StateError('AcpSessionRuntime has no open session yet.');
    }
    return session.updates;
  }

  /// Permission cards surfaced by the agent during the open session.
  @override
  Stream<AgentPermissionRequest> get permissionRequests {
    final session = _session;
    if (session == null) {
      throw StateError('AcpSessionRuntime has no open session yet.');
    }
    return session.permissionRequests;
  }

  /// The live session's agent-process exit code, if observable.
  @override
  Future<int>? get agentProcessExitCode =>
      _session?.connection.agentProcessExitCode;

  /// Answers the currently held permission request (if any).
  @override
  Future<AgentPermissionReplyKind?> answerPermission(
    AgentPermissionReplyKind reply, {
    AgentPermissionAlwaysOption? always,
  }) => _session!.answerPermission(reply, always: always);

  /// Cancels the current prompt turn.
  @override
  void cancel() => _session!.cancel();

  /// Disposes the open session (if any) and the agent connection (if any).
  ///
  /// Safe to call before [start] and idempotent afterwards.
  @override
  Future<void> close() async {
    _session?.dispose();
    _session = null;
    final connection = _connection;
    _connection = null;
    await connection?.dispose();
  }
}
