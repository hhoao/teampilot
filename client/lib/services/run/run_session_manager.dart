import 'dart:async';

import 'package:uuid/uuid.dart';

import '../../models/run/launch_config_document.dart';
import '../../models/run/launch_configuration.dart';
import '../../models/run/run_session.dart';
import 'launch_variable_expander.dart';
import 'process_launch_schema.dart';
import 'process_run_executor.dart';
import 'run_target_resolver.dart';

/// Handle returned by process and adapter launchers.
class RunLaunchHandle {
  const RunLaunchHandle({
    required this.exitCode,
    required this.stop,
  });

  final Future<int> exitCode;
  final Future<void> Function() stop;
}

/// Injectable process launcher for [RunSessionManager].
abstract class RunProcessLauncher {
  Future<RunLaunchHandle> launch({
    required String sessionId,
    required OwnedLaunchConfiguration owned,
    required void Function(ProcessRunOutput output) onOutput,
  });
}

/// Injectable adapter launcher for non-`process` types (Task 6).
abstract class RunAdapterLauncher {
  Future<RunLaunchHandle> launch({
    required String sessionId,
    required OwnedLaunchConfiguration owned,
    required void Function(ProcessRunOutput output) onOutput,
  });
}

/// Default [RunProcessLauncher] backed by [ProcessRunExecutor].
class DefaultRunProcessLauncher implements RunProcessLauncher {
  DefaultRunProcessLauncher({
    ProcessRunExecutor? executor,
    RunTargetResolver? resolver,
  }) : _executor = executor ?? ProcessRunExecutor(),
       _resolver = resolver ?? const RunTargetResolver();

  final ProcessRunExecutor _executor;
  final RunTargetResolver _resolver;

  @override
  Future<RunLaunchHandle> launch({
    required String sessionId,
    required OwnedLaunchConfiguration owned,
    required void Function(ProcessRunOutput output) onOutput,
  }) async {
    final expanded = LaunchVariableExpander.expandConfiguration(
      owned.configuration,
      workspaceFolder: owned.owner.path,
      env: owned.configuration.env,
    );
    final errors = ProcessLaunchSchema.validate(expanded);
    if (errors.isNotEmpty) {
      throw StateError(errors.join('; '));
    }

    final plan = _resolver.resolve(
      owner: owned.owner,
      cwd: expanded.cwd,
      env: expanded.env,
    );
    final result = await _executor.start(
      sessionId: sessionId,
      command: expanded.command!,
      args: expanded.args,
      plan: plan,
      env: expanded.env,
      shell: expanded.shell ?? false,
      onOutput: onOutput,
    );
    return RunLaunchHandle(exitCode: result.exitCode, stop: result.stop);
  }
}

class _StubRunAdapterLauncher implements RunAdapterLauncher {
  const _StubRunAdapterLauncher();

  @override
  Future<RunLaunchHandle> launch({
    required String sessionId,
    required OwnedLaunchConfiguration owned,
    required void Function(ProcessRunOutput output) onOutput,
  }) {
    throw UnimplementedError('Launch adapter: Task 6');
  }
}

class _ActiveRun {
  const _ActiveRun({required this.stop});

  final Future<void> Function() stop;
}

/// Manages parallel workspace run sessions, compounds, stop, and restart.
class RunSessionManager {
  RunSessionManager({
    RunProcessLauncher? executor,
    RunAdapterLauncher? adapters,
    String Function()? uuidFactory,
  }) : _processLauncher = executor ?? DefaultRunProcessLauncher(),
       _adapterLauncher = adapters ?? const _StubRunAdapterLauncher(),
       _uuidFactory = uuidFactory ?? (() => const Uuid().v4());

  final RunProcessLauncher _processLauncher;
  final RunAdapterLauncher _adapterLauncher;
  final String Function() _uuidFactory;

  final Map<String, RunSession> _sessions = {};
  final Map<String, _ActiveRun> _activeRuns = {};
  final StreamController<List<RunSession>> _sessionsController =
      StreamController<List<RunSession>>.broadcast();

  List<String> _lastCompoundErrors = const [];

  /// Emits an immutable snapshot whenever session state changes.
  Stream<List<RunSession>> get sessionsStream => _sessionsController.stream;

  List<RunSession> get sessions =>
      List<RunSession>.unmodifiable(_sessions.values);

  List<String> get lastCompoundErrors =>
      List<String>.unmodifiable(_lastCompoundErrors);

  RunSession? session(String id) => _sessions[id];

  bool hasRunning(String selectionKey) => _sessions.values.any(
    (session) =>
        session.selectionKey == selectionKey &&
        session.status == RunSessionStatus.running,
  );

  Future<RunSession> start(
    OwnedLaunchConfiguration owned, {
    String? compoundId,
  }) async {
    final sessionId = _uuidFactory();
    _upsert(
      RunSession(
        id: sessionId,
        owned: owned,
        status: RunSessionStatus.starting,
        compoundId: compoundId,
      ),
    );

    try {
      final handle = await _launchForType(
        sessionId: sessionId,
        owned: owned,
        onOutput: (_) {},
      );
      _activeRuns[sessionId] = _ActiveRun(stop: handle.stop);
      _upsert(_sessions[sessionId]!.copyWith(status: RunSessionStatus.running));
      unawaited(_watchExit(sessionId: sessionId, handle: handle));
      return _sessions[sessionId]!;
    } catch (error) {
      _activeRuns.remove(sessionId);
      final failed = _sessions[sessionId]!.copyWith(
        status: RunSessionStatus.failed,
        errorMessage: error.toString(),
      );
      _upsert(failed);
      rethrow;
    }
  }

  Future<void> stop(String sessionId) async {
    final active = _activeRuns.remove(sessionId);
    if (active != null) {
      await active.stop();
    }

    final current = _sessions[sessionId];
    if (current == null) return;
    if (current.status == RunSessionStatus.running ||
        current.status == RunSessionStatus.starting) {
      _upsert(current.copyWith(status: RunSessionStatus.exited));
    }
  }

  Future<RunSession> restart(String sessionId) async {
    final current = _sessions[sessionId];
    if (current == null) {
      throw StateError('unknown session: $sessionId');
    }
    await stop(sessionId);
    return start(current.owned, compoundId: current.compoundId);
  }

  Future<List<String>> startCompound({
    required LaunchCompound compound,
    required List<OwnedLaunchConfiguration> documentConfigs,
  }) async {
    _lastCompoundErrors = [];
    final byId = {
      for (final config in documentConfigs) config.configId: config,
    };
    final startedIds = <String>[];
    final errors = <String>[];

    for (final configId in compound.configurationIds) {
      final owned = byId[configId];
      if (owned == null) {
        errors.add('missing configuration: $configId');
        continue;
      }

      try {
        final session = await start(owned, compoundId: compound.id);
        startedIds.add(session.id);
      } catch (error) {
        errors.add(error.toString());
      }
    }

    _lastCompoundErrors = errors;
    return startedIds;
  }

  Future<void> stopCompound(List<String> sessionIds) async {
    for (final sessionId in sessionIds) {
      await stop(sessionId);
    }
  }

  Future<void> dispose() async {
    final activeIds = _activeRuns.keys.toList();
    for (final sessionId in activeIds) {
      await stop(sessionId);
    }
    await _sessionsController.close();
  }

  Future<RunLaunchHandle> _launchForType({
    required String sessionId,
    required OwnedLaunchConfiguration owned,
    required void Function(ProcessRunOutput output) onOutput,
  }) {
    if (owned.configuration.type == ProcessLaunchSchema.typeName) {
      return _processLauncher.launch(
        sessionId: sessionId,
        owned: owned,
        onOutput: onOutput,
      );
    }
    return _adapterLauncher.launch(
      sessionId: sessionId,
      owned: owned,
      onOutput: onOutput,
    );
  }

  Future<void> _watchExit({
    required String sessionId,
    required RunLaunchHandle handle,
  }) async {
    try {
      final code = await handle.exitCode;
      final wasActive = _activeRuns.remove(sessionId);
      if (wasActive != null) {
        await wasActive.stop();
      }

      final current = _sessions[sessionId];
      if (current == null || current.status != RunSessionStatus.running) {
        return;
      }
      _upsert(
        current.copyWith(status: RunSessionStatus.exited, exitCode: code),
      );
    } catch (_) {
      _activeRuns.remove(sessionId);
      final current = _sessions[sessionId];
      if (current == null || current.status != RunSessionStatus.running) {
        return;
      }
      _upsert(current.copyWith(status: RunSessionStatus.exited));
    }
  }

  void _upsert(RunSession session) {
    _sessions[session.id] = session;
    if (!_sessionsController.isClosed) {
      _sessionsController.add(sessions);
    }
  }
}
