import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';

import '../../models/runtime_target.dart';
import '../host/host_shell_argv.dart';
import '../host/host_wsl_argv.dart';
import '../session/launch_command_builder.dart';
import '../storage/remote_file_store.dart';
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

/// Opens a streaming SSH exec for a run on an `ssh:*` folder target.
typedef SshProcessSpawner =
    Future<ProcessRunHandle> Function({
      required String sshProfileId,
      required String shellCommand,
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

/// [ProcessRunHandle] over a dartssh2 [SSHSession] (non-PTY exec).
class SshProcessRunHandle implements ProcessRunHandle {
  SshProcessRunHandle(this._session);

  final SSHSession _session;

  @override
  Future<int> get exitCode async {
    await _session.done;
    return _session.exitCode ?? 0;
  }

  @override
  Stream<List<int>> get stdout => _session.stdout.map(_asList);

  @override
  Stream<List<int>> get stderr => _session.stderr.map(_asList);

  @override
  void kill() {
    try {
      _session.kill(SSHSignal.KILL);
    } catch (_) {
      _session.close();
    }
  }

  static List<int> _asList(Uint8List data) => data;
}

class ProcessRunResult {
  const ProcessRunResult({
    required this.exitCode,
    required this.stop,
  });

  final Future<int> exitCode;
  final Future<void> Function() stop;
}

/// Spawns built-in `process` launch configs on the resolved local / WSL / SSH
/// target (mirrors [WorkspaceShellConnector] transport selection).
class ProcessRunExecutor {
  ProcessRunExecutor({
    ProcessSpawner? spawner,
    SshProcessSpawner? sshSpawner,
  }) : _spawner = spawner ?? _defaultSpawner,
       _sshSpawner = sshSpawner;

  final ProcessSpawner _spawner;
  final SshProcessSpawner? _sshSpawner;

  Future<ProcessRunResult> start({
    required String sessionId,
    required String command,
    required List<String> args,
    required RunTargetPlan plan,
    Map<String, String>? env,
    bool shell = false,
    required void Function(ProcessRunOutput output) onOutput,
  }) async {
    final handle = await _spawn(
      command: command,
      args: args,
      plan: plan,
      env: env,
      shell: shell,
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

  Future<ProcessRunHandle> _spawn({
    required String command,
    required List<String> args,
    required RunTargetPlan plan,
    Map<String, String>? env,
    required bool shell,
  }) {
    final launchEnv = LaunchCommandBuilder.launchEnvironmentForProcess(env);
    return switch (plan.runtimeTarget.kind) {
      RuntimeKind.local => _spawner(
        executable: command,
        arguments: args,
        workingDirectory: plan.hostProcessWorkingDirectory,
        environment: launchEnv,
        runInShell: shell,
        includeParentEnvironment: true,
      ),
      RuntimeKind.wsl => _spawnWsl(
        command: command,
        args: args,
        plan: plan,
        environment: launchEnv,
        shell: shell,
      ),
      RuntimeKind.ssh => _spawnSsh(
        command: command,
        args: args,
        plan: plan,
        environment: launchEnv,
      ),
    };
  }

  Future<ProcessRunHandle> _spawnWsl({
    required String command,
    required List<String> args,
    required RunTargetPlan plan,
    Map<String, String>? environment,
    required bool shell,
  }) {
    final String executable;
    final List<String> arguments;
    if (shell) {
      final script = [
        command,
        ...args,
      ].map(RemoteFileStore.shellSingleQuote).join(' ');
      executable = 'wsl.exe';
      arguments = HostWslArgv.processInvocation(
        distro: plan.runtimeTarget.wslDistro,
        workingDirectory: plan.workingDirectory,
        executable: 'sh',
        arguments: ['-c', script],
      );
    } else {
      executable = 'wsl.exe';
      arguments = HostWslArgv.processInvocation(
        distro: plan.runtimeTarget.wslDistro,
        workingDirectory: plan.workingDirectory,
        executable: command,
        arguments: args,
      );
    }

    return _spawner(
      executable: executable,
      arguments: arguments,
      workingDirectory: plan.hostProcessWorkingDirectory,
      environment: environment,
      runInShell: false,
      includeParentEnvironment: true,
    );
  }

  Future<ProcessRunHandle> _spawnSsh({
    required String command,
    required List<String> args,
    required RunTargetPlan plan,
    Map<String, String>? environment,
  }) {
    final opener = _sshSpawner;
    if (opener == null) {
      throw StateError('SSH process execution is not configured');
    }
    final profileId = plan.runtimeTarget.sshProfileId?.trim() ?? '';
    if (profileId.isEmpty) {
      throw StateError('SSH profile not found for this run target');
    }
    final shellCommand = HostShellArgv.command(
      executable: command,
      arguments: args,
      workingDirectory: plan.workingDirectory,
      environment: environment,
    );
    return opener(sshProfileId: profileId, shellCommand: shellCommand);
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
