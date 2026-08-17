import 'dart:io';

import 'host_one_shot_runner.dart';
import 'host_tty_wrap.dart';
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
  LocalHostProcessStarter({
    HostProcessSpawner? spawner,
    HostTtyScriptFlavor? ttyFlavor,
  }) : _spawner = spawner ?? _defaultSpawner,
       _ttyFlavor = ttyFlavor ?? _defaultTtyFlavor;

  final HostProcessSpawner _spawner;
  final HostTtyScriptFlavor _ttyFlavor;

  static HostTtyScriptFlavor get _defaultTtyFlavor {
    if (Platform.isMacOS) return HostTtyScriptFlavor.bsd;
    return HostTtyScriptFlavor.gnu;
  }

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
    final launched = Platform.isWindows
        ? request
        : HostTtyWrap.apply(request, flavor: _ttyFlavor);
    return _spawner(
      executable: launched.executable,
      arguments: launched.arguments,
      workingDirectory: launched.workingDirectory,
      environment: launched.environment,
      includeParentEnvironment: launched.includeParentEnvironment,
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
    final launched = HostTtyWrap.apply(
      request,
      flavor: HostTtyScriptFlavor.gnu,
    );
    final env = launched.environment;
    final executable = env != null && env.isNotEmpty ? 'env' : launched.executable;
    final arguments = env != null && env.isNotEmpty
        ? [
            ...env.entries.map((e) => '${e.key}=${e.value}'),
            launched.executable,
            ...launched.arguments,
          ]
        : launched.arguments;
    final args = HostWslArgv.processInvocation(
      distro: _distro,
      workingDirectory: launched.workingDirectory,
      executable: executable,
      arguments: arguments,
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
    final launched = HostTtyWrap.apply(
      request,
      flavor: HostTtyScriptFlavor.gnu,
    );
    final command = HostShellArgv.command(
      executable: launched.executable,
      arguments: launched.arguments,
      workingDirectory: launched.workingDirectory,
      environment: launched.environment,
    );
    return _startShell(command);
  }
}
