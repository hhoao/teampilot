import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../models/runtime_target.dart';
import '../session/launch_command_builder.dart';
import 'run_target_resolver.dart';

/// One chunk of child process output for a run session.
@immutable
class ProcessRunOutput {
  const ProcessRunOutput({
    required this.sessionId,
    required this.category,
    required this.data,
  });

  final String sessionId;
  final String category;
  final String data;
}

/// Abstraction over a spawned child process for tests and production.
abstract class ProcessRunHandle {
  Future<int> get exitCode;
  Stream<List<int>> get stdout;
  Stream<List<int>> get stderr;
  void kill();
}

/// Injected process starter — keeps [ProcessRunExecutor] free of raw
/// [Process.start] in unit tests.
typedef ProcessSpawner =
    Future<ProcessRunHandle> Function({
      required String executable,
      required List<String> arguments,
      required String workingDirectory,
      Map<String, String>? environment,
      bool runInShell,
      bool includeParentEnvironment,
    });

class _ProcessRunHandle implements ProcessRunHandle {
  _ProcessRunHandle(this._process);

  final Process _process;

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  Stream<List<int>> get stdout => _process.stdout;

  @override
  Stream<List<int>> get stderr => _process.stderr;

  @override
  void kill() => _process.kill();
}

class ProcessRunResult {
  const ProcessRunResult({
    required this.exitCode,
    required this.stop,
  });

  final Future<int> exitCode;
  final Future<void> Function() stop;
}

/// Spawns built-in `process` launch configs on the resolved local target.
class ProcessRunExecutor {
  ProcessRunExecutor({ProcessSpawner? spawner})
    : _spawner = spawner ?? _defaultSpawner;

  final ProcessSpawner _spawner;

  Future<ProcessRunResult> start({
    required String sessionId,
    required String command,
    required List<String> args,
    required RunTargetPlan plan,
    Map<String, String>? env,
    bool shell = false,
    required void Function(ProcessRunOutput output) onOutput,
  }) async {
    if (plan.runtimeTarget.kind != RuntimeKind.local) {
      throw UnsupportedError('remote process execution: Task 10');
    }

    final handle = await _spawner(
      executable: command,
      arguments: args,
      workingDirectory: plan.workingDirectory,
      environment: LaunchCommandBuilder.launchEnvironmentForProcess(env),
      runInShell: shell,
      includeParentEnvironment: true,
    );

    final subscriptions = <StreamSubscription<List<int>>>[];
    void emit(String category, List<int> data) {
      if (data.isEmpty) return;
      onOutput(
        ProcessRunOutput(
          sessionId: sessionId,
          category: category,
          data: utf8.decode(data, allowMalformed: true),
        ),
      );
    }

    subscriptions.add(handle.stdout.listen((data) => emit('stdout', data)));
    subscriptions.add(handle.stderr.listen((data) => emit('stderr', data)));

    Future<void> stop() async {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
      handle.kill();
    }

    return ProcessRunResult(exitCode: handle.exitCode, stop: stop);
  }

  static Future<ProcessRunHandle> _defaultSpawner({
    required String executable,
    required List<String> arguments,
    required String workingDirectory,
    Map<String, String>? environment,
    bool runInShell = false,
    bool includeParentEnvironment = true,
  }) async {
    final cwd = workingDirectory.trim();
    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: cwd.isEmpty ? null : cwd,
      environment: environment,
      runInShell: runInShell,
      includeParentEnvironment: includeParentEnvironment,
    );
    return _ProcessRunHandle(process);
  }
}
