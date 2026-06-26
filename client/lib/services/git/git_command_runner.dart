import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';

import '../cli/cli_tool_locator.dart';
import '../host/host_one_shot_runner.dart';
import '../ssh/ssh_run_result.dart';
import '../storage/remote_file_store.dart';
import '../storage/runtime_context.dart';

/// Result of one `git -C <dir> …` invocation.
class GitCommandResult {
  const GitCommandResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}

GitCommandResult _gitResultFromHost(HostRunResult result) {
  return GitCommandResult(
    exitCode: result.exitCode,
    stdout: result.stdout,
    stderr: result.stderr,
  );
}

/// Executes git against a working directory on local disk, WSL, or SSH.
abstract interface class GitCommandRunner {
  Future<bool> get isAvailable;

  Future<GitCommandResult> runInDirectory(String dir, List<String> args);
}

/// Shared git flags prepended to every invocation (see [GitService]).
const List<String> gitGlobalFlags = [
  '--no-optional-locks',
  '-c',
  'core.quotePath=false',
];

List<String> _gitArgv(String dir, List<String> args) {
  return [...gitGlobalFlags, '-C', dir, ...args];
}

class LocalGitCommandRunner implements GitCommandRunner {
  LocalGitCommandRunner({
    ProcessRunner runner = cliToolDefaultProcessRun,
    CliToolLocator? gitLocator,
    HostOneShotRunner? hostRunner,
  })  : _runner = runner,
        _gitLocator = gitLocator ?? const CliToolLocator('git'),
        _host = hostRunner ?? LocalHostOneShotRunner();

  final ProcessRunner _runner;
  final CliToolLocator _gitLocator;
  final HostOneShotRunner _host;

  static Future<String?>? _locateFuture;

  static void debugResetExecutableCache() => _locateFuture = null;

  Future<String?> get _git =>
      _locateFuture ??= _gitLocator.locate(runner: _runner);

  @override
  Future<bool> get isAvailable async => (await _git) != null;

  @override
  Future<GitCommandResult> runInDirectory(String dir, List<String> args) async {
    final git = await _git;
    if (git == null) {
      return const GitCommandResult(
        exitCode: 127,
        stdout: '',
        stderr: 'git executable not found on PATH',
      );
    }
    final result = await _host.run(
      HostRunRequest(executable: git, arguments: _gitArgv(dir, args)),
    );
    return _gitResultFromHost(result);
  }
}

class WslGitCommandRunner implements GitCommandRunner {
  WslGitCommandRunner({
    String? distro,
    ProcessRunner? wslRunner,
    HostOneShotRunner? hostRunner,
  })  : _host =
            hostRunner ??
            WslHostOneShotRunner(
              distro: distro,
              processRunner: _adaptProcessRunner(wslRunner),
            );

  final HostOneShotRunner _host;

  static HostProcessRunner _adaptProcessRunner(ProcessRunner? wslRunner) {
    final runner = wslRunner ?? Process.run;
    return (
      executable,
      arguments, {
      workingDirectory,
      environment,
      includeParentEnvironment = true,
      stdoutEncoding,
      stderrEncoding,
    }) {
      return runner(
        executable,
        arguments,
        stdoutEncoding: stdoutEncoding ?? const Utf8Codec(allowMalformed: true),
        stderrEncoding: stderrEncoding ?? const Utf8Codec(allowMalformed: true),
      );
    };
  }

  @override
  Future<bool> get isAvailable async {
    final result = await _host.run(
      const HostRunRequest(
        executable: 'sh',
        arguments: ['-lc', 'command -v git >/dev/null 2>&1 || which git'],
      ),
    );
    return result.succeeded && result.stdout.trim().isNotEmpty;
  }

  @override
  Future<GitCommandResult> runInDirectory(String dir, List<String> args) async {
    final result = await _host.run(
      HostRunRequest(
        executable: 'git',
        arguments: _gitArgv(dir, args),
      ),
    );
    return _gitResultFromHost(result);
  }
}

class RemoteGitCommandRunner implements GitCommandRunner {
  RemoteGitCommandRunner({
    RemoteFileStore? store,
    Future<SSHRunResult> Function(String command)? execShell,
    HostOneShotRunner? hostRunner,
  }) : assert(
         store != null || execShell != null,
         'store or execShell required',
       ),
       _execShell = execShell ?? store!.execShell,
       _host =
           hostRunner ??
           RemoteHostOneShotRunner(
             execShell: execShell ?? store!.execShell,
           );

  final Future<SSHRunResult> Function(String command) _execShell;
  final HostOneShotRunner _host;

  static Future<bool>? _availableFuture;

  static void debugResetAvailabilityCache() => _availableFuture = null;

  @override
  Future<bool> get isAvailable =>
      _availableFuture ??= _probeAvailability();

  Future<bool> _probeAvailability() async {
    final result = await _execShell(
      'command -v git >/dev/null 2>&1 || which git 2>/dev/null',
    );
    if (sshRunFailed(result)) return false;
    return utf8.decode(result.stdout, allowMalformed: true).trim().isNotEmpty;
  }

  @override
  Future<GitCommandResult> runInDirectory(String dir, List<String> args) async {
    final result = await _host.run(
      HostRunRequest(
        executable: 'git',
        arguments: _gitArgv(dir, args),
      ),
    );
    return _gitResultFromHost(result);
  }
}

/// Picks the git runner for the active [RuntimeContext] storage backend.
GitCommandRunner gitCommandRunnerForContext(RuntimeContext ctx) {
  return switch (ctx.mode) {
    StorageBackendMode.ssh => RemoteGitCommandRunner(
      store: ctx.remoteFileStore!,
    ),
    StorageBackendMode.wsl => WslGitCommandRunner(
      distro: ctx.target.wslDistro,
    ),
    StorageBackendMode.native => LocalGitCommandRunner(),
  };
}
