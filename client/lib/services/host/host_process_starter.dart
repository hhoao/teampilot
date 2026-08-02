import 'dart:io';

import 'host_one_shot_runner.dart';
import 'process_run_handle.dart';

typedef HostProcessSpawner =
    Future<ProcessRunHandle> Function({
      required String executable,
      required List<String> arguments,
      String? workingDirectory,
      Map<String, String>? environment,
      bool includeParentEnvironment,
    });

/// Starts a streaming child process on native disk, WSL, or SSH.
abstract interface class HostProcessStarter {
  Future<ProcessRunHandle> start(HostRunRequest request);
}

class LocalHostProcessStarter implements HostProcessStarter {
  LocalHostProcessStarter({HostProcessSpawner? spawner})
    : _spawner = spawner ?? _defaultSpawner;

  final HostProcessSpawner _spawner;

  static Future<ProcessRunHandle> _defaultSpawner({
    required String executable,
    required List<String> arguments,
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
  }) async {
    final cwd = workingDirectory?.trim() ?? '';
    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: cwd.isEmpty ? null : cwd,
      environment: environment,
      includeParentEnvironment: includeParentEnvironment,
    );
    return LocalProcessRunHandle(process);
  }

  @override
  Future<ProcessRunHandle> start(HostRunRequest request) {
    return _spawner(
      executable: request.executable,
      arguments: request.arguments,
      workingDirectory: request.workingDirectory,
      environment: request.environment,
      includeParentEnvironment: request.includeParentEnvironment,
    );
  }
}

class WslHostProcessStarter implements HostProcessStarter {
  WslHostProcessStarter({String? distro, HostProcessSpawner? spawner})
    : _distro = distro?.trim(),
      _spawner = spawner ?? LocalHostProcessStarter._defaultSpawner;

  final String? _distro;
  final HostProcessSpawner _spawner;

  @override
  Future<ProcessRunHandle> start(HostRunRequest request) {
    final args = HostWslArgv.processInvocation(
      distro: _distro,
      workingDirectory: request.workingDirectory,
      executable: request.executable,
      arguments: request.arguments,
    );
    return _spawner(
      executable: 'wsl.exe',
      arguments: args,
      includeParentEnvironment: request.includeParentEnvironment,
    );
  }
}

class RemoteHostProcessStarter implements HostProcessStarter {
  RemoteHostProcessStarter({
    required Future<ProcessRunHandle> Function(String command) startShell,
  }) : _startShell = startShell;

  final Future<ProcessRunHandle> Function(String command) _startShell;

  @override
  Future<ProcessRunHandle> start(HostRunRequest request) {
    final command = HostShellArgv.command(
      executable: request.executable,
      arguments: request.arguments,
      workingDirectory: request.workingDirectory,
      environment: request.environment,
    );
    return _startShell(command);
  }
}
