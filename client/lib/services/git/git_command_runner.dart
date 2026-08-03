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

HostProcessRunner _hostProcessRunnerFrom(ProcessRunner runner) {
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

/// Optional absolute/bare git from SessionPreferences.toolchainPaths['git'].
/// Empty/null → auto-discover. Set from app_shell; cleared in tests.
String? Function()? configuredGitExecutable;

String? _resolvedConfiguredGit([String? override]) {
  final raw = (override ?? configuredGitExecutable?.call())?.trim();
  if (raw == null || raw.isEmpty) return null;
  return raw;
}

/// Picks the git runner for the active [RuntimeContext] storage backend.
GitCommandRunner gitCommandRunnerForContext(
  RuntimeContext ctx, {
  String? gitExecutable,
}) {
  final exe = _resolvedConfiguredGit(gitExecutable);
  return switch (ctx.mode) {
    StorageBackendMode.ssh => RemoteGitCommandRunner(
      store: ctx.remoteFileStore!,
      hostKey: ctx.target.id,
      gitExecutable: exe,
    ),
    StorageBackendMode.wsl => WslGitCommandRunner(
      distro: ctx.target.wslDistro,
      gitExecutable: exe,
    ),
    StorageBackendMode.native => LocalGitCommandRunner(gitExecutable: exe),
  };
}

class LocalGitCommandRunner implements GitCommandRunner {
  LocalGitCommandRunner({
    String? gitExecutable,
    ProcessRunner runner = cliToolDefaultProcessRun,
    CliToolLocator? gitLocator,
    HostOneShotRunner? hostRunner,
  }) : _configuredExe = _resolvedConfiguredGit(gitExecutable),
       _runner = runner,
       _gitLocator = gitLocator ?? const CliToolLocator('git') {
    _host =
        hostRunner ??
        LocalHostOneShotRunner(processRunner: _hostProcessRunnerFrom(runner));
  }

  final String? _configuredExe;
  final ProcessRunner _runner;
  final CliToolLocator _gitLocator;
  late final HostOneShotRunner _host;

  static Future<String?>? _locateFuture;

  static void debugResetExecutableCache() => _locateFuture = null;

  Future<String?> get _git async {
    final configured = _configuredExe;
    if (configured != null) return configured;
    return _locateFuture ??= _gitLocator.locate(runner: _runner);
  }

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
    String? gitExecutable,
    ProcessRunner? wslRunner,
    HostOneShotRunner? hostRunner,
  }) : _exe = _resolvedConfiguredGit(gitExecutable),
       _host =
           hostRunner ??
           WslHostOneShotRunner(
             distro: distro,
             processRunner: _hostProcessRunnerFrom(wslRunner ?? Process.run),
           );

  final String? _exe;
  final HostOneShotRunner _host;

  String get _git => _exe ?? 'git';

  @override
  Future<bool> get isAvailable async {
    if (_exe != null) {
      final exe = _git;
      final result = await _host.run(
        HostRunRequest(
          executable: 'sh',
          arguments: [
            '-lc',
            "test -x '$exe' || command -v '$exe' >/dev/null 2>&1",
          ],
        ),
      );
      return result.succeeded;
    }
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
      HostRunRequest(executable: _git, arguments: _gitArgv(dir, args)),
    );
    return _gitResultFromHost(result);
  }
}

class RemoteGitCommandRunner implements GitCommandRunner {
  RemoteGitCommandRunner({
    RemoteFileStore? store,
    Future<SSHRunResult> Function(String command)? execShell,
    HostOneShotRunner? hostRunner,
    String? hostKey,
    String? gitExecutable,
  }) : assert(
         store != null || execShell != null,
         'store or execShell required',
       ),
       _execShell = execShell ?? store!.execShell,
       _hostKey = hostKey ?? '',
       _exe = _resolvedConfiguredGit(gitExecutable),
       _host =
           hostRunner ??
           RemoteHostOneShotRunner(execShell: execShell ?? store!.execShell);

  final Future<SSHRunResult> Function(String command) _execShell;
  final HostOneShotRunner _host;

  /// Identifies the remote host so the availability probe is cached per host
  /// (a host without git must not poison the cache for every other host).
  final String _hostKey;
  final String? _exe;

  String get _git => _exe ?? 'git';

  String get _availabilityCacheKey => '$_hostKey|$_git';

  static final Map<String, Future<bool>> _availableByHost = {};

  static void debugResetAvailabilityCache() => _availableByHost.clear();

  @override
  Future<bool> get isAvailable =>
      _availableByHost[_availabilityCacheKey] ??= _probeAvailability();

  Future<bool> _probeAvailability() async {
    final exe = _git;
    final probe = _exe != null
        ? "test -x '$exe' || command -v '$exe' >/dev/null 2>&1"
        : 'command -v git >/dev/null 2>&1 || which git 2>/dev/null';
    final result = await _execShell(probe);
    if (sshRunFailed(result)) return false;
    if (_exe != null) return true;
    return utf8.decode(result.stdout, allowMalformed: true).trim().isNotEmpty;
  }

  @override
  Future<GitCommandResult> runInDirectory(String dir, List<String> args) async {
    final result = await _host.run(
      HostRunRequest(executable: _git, arguments: _gitArgv(dir, args)),
    );
    return _gitResultFromHost(result);
  }
}
