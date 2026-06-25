import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';

import '../cli/cli_tool_locator.dart';
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

class LocalGitCommandRunner implements GitCommandRunner {
  LocalGitCommandRunner({
    ProcessRunner runner = cliToolDefaultProcessRun,
    CliToolLocator? gitLocator,
  })  : _runner = runner,
        _gitLocator = gitLocator ?? const CliToolLocator('git');

  final ProcessRunner _runner;
  final CliToolLocator _gitLocator;

  static const Encoding _textEncoding = Utf8Codec(allowMalformed: true);

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
    final result = await _runner(
      git,
      [...gitGlobalFlags, '-C', dir, ...args],
      stdoutEncoding: _textEncoding,
      stderrEncoding: _textEncoding,
    );
    return GitCommandResult(
      exitCode: result.exitCode,
      stdout: (result.stdout as String?) ?? '',
      stderr: (result.stderr as String?) ?? '',
    );
  }
}

class WslGitCommandRunner implements GitCommandRunner {
  WslGitCommandRunner({
    String? distro,
    ProcessRunner? wslRunner,
  })  : _distro = distro?.trim(),
        _wslRunner = wslRunner ?? Process.run;

  final String? _distro;
  final ProcessRunner _wslRunner;

  static const Encoding _textEncoding = Utf8Codec(allowMalformed: true);

  List<String> _wslArgs(List<String> command) {
    final distro = _distro;
    if (distro == null || distro.isEmpty) return command;
    return ['-d', distro, ...command];
  }

  @override
  Future<bool> get isAvailable async {
    final result = await _wslRunner(
      'wsl.exe',
      _wslArgs(['sh', '-lc', 'command -v git >/dev/null 2>&1 || which git']),
      stdoutEncoding: _textEncoding,
      stderrEncoding: _textEncoding,
    );
    return result.exitCode == 0 &&
        (result.stdout as String?)?.trim().isNotEmpty == true;
  }

  @override
  Future<GitCommandResult> runInDirectory(String dir, List<String> args) async {
    final argv = <String>[
      'git',
      ...gitGlobalFlags,
      '-C',
      dir,
      ...args,
    ];
    final result = await _wslRunner(
      'wsl.exe',
      _wslArgs(argv),
      stdoutEncoding: _textEncoding,
      stderrEncoding: _textEncoding,
    );
    return GitCommandResult(
      exitCode: result.exitCode,
      stdout: (result.stdout as String?) ?? '',
      stderr: (result.stderr as String?) ?? '',
    );
  }
}

class RemoteGitCommandRunner implements GitCommandRunner {
  RemoteGitCommandRunner({
    RemoteFileStore? store,
    Future<SSHRunResult> Function(String command)? execShell,
  }) : assert(
         store != null || execShell != null,
         'store or execShell required',
       ),
       _execShell = execShell ?? store!.execShell;

  final Future<SSHRunResult> Function(String command) _execShell;

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
    final shellArgs = <String>[
      'git',
      ...gitGlobalFlags,
      '-C',
      dir,
      ...args,
    ];
    final cmd = shellArgs.map(RemoteFileStore.shellSingleQuote).join(' ');
    final result = await _execShell(cmd);
    return GitCommandResult(
      exitCode: result.exitCode ?? 1,
      stdout: utf8.decode(result.stdout, allowMalformed: true),
      stderr: utf8.decode(result.stderr, allowMalformed: true),
    );
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
