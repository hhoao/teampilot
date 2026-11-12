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

/// Result of one raw git invocation; [stdout] stays undecoded because callers
/// such as `git show` need to tell text from binary blobs.
class GitRawResult {
  const GitRawResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final List<int> stdout;
  final String stderr;

  bool get succeeded => exitCode == 0;
}

/// What the installed git can do, derived from `git --version`.
class GitCapability {
  const GitCapability({
    required this.available,
    this.version,
    this.pathspecFromFile = false,
  });

  final bool available;
  final String? version;
  final bool pathspecFromFile;

  static const unavailable = GitCapability(available: false);
}

/// Parses `git --version` output into a [GitCapability]. Shared by all runners.
GitCapability gitCapabilityFromVersion(GitRawResult result) {
  if (result.exitCode != 0) return GitCapability.unavailable;
  final text = utf8.decode(result.stdout, allowMalformed: true).trim();
  final match = RegExp(r'git version (\d+)\.(\d+)').firstMatch(text);
  final major = int.tryParse(match?.group(1) ?? '') ?? 0;
  final minor = int.tryParse(match?.group(2) ?? '') ?? 0;
  return GitCapability(
    available: true,
    version: match == null ? text : '${match.group(1)}.${match.group(2)}',
    pathspecFromFile: major > 2 || (major == 2 && minor >= 25),
  );
}

GitCommandResult _gitResultFromHost(HostRunResult result) {
  return GitCommandResult(
    exitCode: result.exitCode,
    stdout: result.stdout,
    stderr: result.stderr,
  );
}

/// Decodes child output that may contain bytes which are not valid UTF-8
/// (git echoes raw paths, for instance).
const Utf8Codec _lenientUtf8 = Utf8Codec(allowMalformed: true);

/// How long to keep draining the output pipes after a timed-out child is
/// killed. The child's own children can inherit the pipes and outlive it, so
/// this wait must be bounded or a timeout would not bound the call.
const Duration _killGrace = Duration(milliseconds: 500);

/// Executes git against a working directory on local disk, WSL, or SSH.
abstract interface class GitCommandRunner {
  Future<bool> get isAvailable;

  Future<GitCommandResult> runInDirectory(
    String dir,
    List<String> args, {
    Map<String, String>? environment,
  });

  /// Runs git with [args] verbatim (no `-C`/global flags added) and returns
  /// undecoded stdout. Throws [StateError] on non-zero exit unless
  /// [allowFailure] is set.
  Future<GitRawResult> runRaw(
    List<String> args, {
    String? workingDirectory,
    Map<String, String>? environment,
    String? stdinText,
    bool allowFailure = false,
    Duration? timeout,
  });

  /// Streams git stdout straight into [destPath], so large blobs never sit in
  /// memory. Throws [StateError] and removes the partial file on failure.
  Future<void> runToFile(
    List<String> args,
    String destPath, {
    String? workingDirectory,
    Map<String, String>? environment,
    Duration? timeout,
  });

  /// Runs an arbitrary POSIX shell [script] on the host (used where one git
  /// invocation is not enough). Throws [StateError] on non-zero exit.
  Future<GitCommandResult> runScript(
    String script, {
    String? workingDirectory,
    Map<String, String>? environment,
    String? stdinText,
    Duration? timeout,
  });

  /// Probes the installed git version/capabilities.
  Future<GitCapability> probe();
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
      environment: environment,
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
  Future<GitCommandResult> runInDirectory(
    String dir,
    List<String> args, {
    Map<String, String>? environment,
  }) async {
    final git = await _git;
    if (git == null) {
      return const GitCommandResult(
        exitCode: 127,
        stdout: '',
        stderr: 'git executable not found on PATH',
      );
    }
    final result = await _host.run(
      HostRunRequest(
        executable: git,
        arguments: _gitArgv(dir, args),
        environment: environment,
      ),
    );
    return _gitResultFromHost(result);
  }

  @override
  Future<GitRawResult> runRaw(
    List<String> args, {
    String? workingDirectory,
    Map<String, String>? environment,
    String? stdinText,
    bool allowFailure = false,
    Duration? timeout,
  }) async {
    final git = await _git;
    if (git == null) {
      return const GitRawResult(
        exitCode: 127,
        stdout: [],
        stderr: 'git executable not found on PATH',
      );
    }
    final process = await Process.start(
      git,
      args,
      workingDirectory: workingDirectory,
      environment: environment,
    );
    final outFuture = process.stdout.fold<List<int>>(
      <int>[],
      (buffer, chunk) => buffer..addAll(chunk),
    );
    final errFuture = process.stderr.transform(_lenientUtf8.decoder).join();
    if (stdinText != null) process.stdin.write(stdinText);
    try {
      await process.stdin.close();
    } on Object {
      // already closed
    }
    var timedOut = false;
    final exit = await process.exitCode.timeout(
      timeout ?? const Duration(seconds: 30),
      onTimeout: () {
        timedOut = true;
        process.kill();
        return -1;
      },
    );
    final stdout = await (timedOut
        ? outFuture.timeout(_killGrace, onTimeout: () => <int>[])
        : outFuture);
    final stderr = await (timedOut
        ? errFuture.timeout(_killGrace, onTimeout: () => '')
        : errFuture);
    if (!allowFailure && (timedOut || exit != 0)) {
      throw StateError('git ${args.join(' ')} failed ($exit): $stderr');
    }
    return GitRawResult(exitCode: exit, stdout: stdout, stderr: stderr);
  }

  @override
  Future<void> runToFile(
    List<String> args,
    String destPath, {
    String? workingDirectory,
    Map<String, String>? environment,
    Duration? timeout,
  }) async {
    final git = await _git;
    if (git == null) {
      throw StateError('git executable not found on PATH');
    }
    final process = await Process.start(
      git,
      args,
      workingDirectory: workingDirectory,
      environment: environment,
    );
    final dest = File(destPath);
    await dest.parent.create(recursive: true);
    final sink = dest.openWrite();
    final pipeFuture = process.stdout.pipe(sink);
    final errFuture = process.stderr.transform(_lenientUtf8.decoder).join();
    var timedOut = false;
    final exit = await process.exitCode.timeout(
      timeout ?? const Duration(seconds: 30),
      onTimeout: () {
        timedOut = true;
        process.kill();
        return -1;
      },
    );
    if (timedOut) {
      await pipeFuture.timeout(_killGrace, onTimeout: () => null);
    } else {
      await pipeFuture;
    }
    final stderr = await (timedOut
        ? errFuture.timeout(_killGrace, onTimeout: () => '')
        : errFuture);
    if (timedOut || exit != 0) {
      if (await dest.exists()) await dest.delete();
      throw StateError('git ${args.join(' ')} failed ($exit): $stderr');
    }
  }

  @override
  Future<GitCommandResult> runScript(
    String script, {
    String? workingDirectory,
    Map<String, String>? environment,
    String? stdinText,
    Duration? timeout,
  }) async {
    if (Platform.isWindows) {
      throw UnsupportedError('runScript is POSIX-only');
    }
    // Not a login shell: profile scripts can abort the shell or write to
    // stdout, which would corrupt the script output callers parse.
    final process = await Process.start(
      'sh',
      ['-c', script],
      workingDirectory: workingDirectory,
      environment: environment,
    );
    final outFuture = process.stdout.transform(_lenientUtf8.decoder).join();
    final errFuture = process.stderr.transform(_lenientUtf8.decoder).join();
    if (stdinText != null) process.stdin.write(stdinText);
    try {
      await process.stdin.close();
    } on Object {
      // already closed
    }
    var timedOut = false;
    final exit = await process.exitCode.timeout(
      timeout ?? const Duration(seconds: 30),
      onTimeout: () {
        timedOut = true;
        process.kill();
        return -1;
      },
    );
    final stdout = await (timedOut
        ? outFuture.timeout(_killGrace, onTimeout: () => '')
        : outFuture);
    final stderr = await (timedOut
        ? errFuture.timeout(_killGrace, onTimeout: () => '')
        : errFuture);
    if (timedOut || exit != 0) {
      throw StateError('sh -lc failed ($exit): $stderr');
    }
    return GitCommandResult(exitCode: exit, stdout: stdout, stderr: stderr);
  }

  @override
  Future<GitCapability> probe() async =>
      gitCapabilityFromVersion(await runRaw(['--version'], allowFailure: true));
}

/// Default WSL spawner: `wsl.exe` is injected so byte streams, stdin and
/// timeouts can be exercised in tests without a Windows host.
Future<Process> _defaultWslProcessStart(
  String executable,
  List<String> arguments,
) => Process.start(executable, arguments);

typedef WslProcessStarter =
    Future<Process> Function(String executable, List<String> arguments);

class WslGitCommandRunner implements GitCommandRunner {
  WslGitCommandRunner({
    String? distro,
    String? gitExecutable,
    ProcessRunner? wslRunner,
    HostOneShotRunner? hostRunner,
    WslProcessStarter? wslProcessStarter,
  }) : _distro = distro?.trim(),
       _spawn = wslProcessStarter ?? _defaultWslProcessStart,
       _exe = _resolvedConfiguredGit(gitExecutable),
       _host =
           hostRunner ??
           WslHostOneShotRunner(
             distro: distro,
             processRunner: _hostProcessRunnerFrom(wslRunner ?? Process.run),
           );

  final String? _distro;
  final WslProcessStarter _spawn;
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
        arguments: [
          '-lc',
          'command -v git 2>/dev/null || which git 2>/dev/null',
        ],
      ),
    );
    return result.succeeded && result.stdout.trim().isNotEmpty;
  }

  /// Builds the `wsl.exe` argv, forwarding cwd via `--cd` and environment via
  /// an `env` prefix (same convention as [WslHostOneShotRunner]).
  List<String> _wslArgv({
    required String executable,
    required List<String> arguments,
    String? workingDirectory,
    Map<String, String>? environment,
  }) {
    final env = environment;
    final exe = env != null && env.isNotEmpty ? 'env' : executable;
    final args = env != null && env.isNotEmpty
        ? [
            ...env.entries.map((e) => '${e.key}=${e.value}'),
            executable,
            ...arguments,
          ]
        : arguments;
    return HostWslArgv.processInvocation(
      distro: _distro,
      workingDirectory: workingDirectory,
      executable: exe,
      arguments: args,
    );
  }

  /// Mirrors [LocalGitCommandRunner]'s drain/timeout semantics: collect raw
  /// stdout bytes, write optional stdin, bound the drain after a kill.
  Future<({List<int> stdout, String stderr, int exitCode, bool timedOut})>
      _runWslProcess(
    List<String> argv, {
    String? stdinText,
    Duration? timeout,
  }) async {
    final process = await _spawn('wsl.exe', argv);
    final outFuture = process.stdout.fold<List<int>>(
      <int>[],
      (buffer, chunk) => buffer..addAll(chunk),
    );
    final errFuture = process.stderr.transform(_lenientUtf8.decoder).join();
    if (stdinText != null) process.stdin.write(stdinText);
    try {
      await process.stdin.close();
    } on Object {
      // already closed
    }
    var timedOut = false;
    final exit = await process.exitCode.timeout(
      timeout ?? const Duration(seconds: 30),
      onTimeout: () {
        timedOut = true;
        process.kill();
        return -1;
      },
    );
    final stdout = await (timedOut
        ? outFuture.timeout(_killGrace, onTimeout: () => <int>[])
        : outFuture);
    final stderr = await (timedOut
        ? errFuture.timeout(_killGrace, onTimeout: () => '')
        : errFuture);
    return (
      stdout: stdout,
      stderr: stderr,
      exitCode: exit,
      timedOut: timedOut,
    );
  }

  @override
  Future<GitRawResult> runRaw(
    List<String> args, {
    String? workingDirectory,
    Map<String, String>? environment,
    String? stdinText,
    bool allowFailure = false,
    Duration? timeout,
  }) async {
    final result = await _runWslProcess(
      _wslArgv(
        executable: _git,
        arguments: args,
        workingDirectory: workingDirectory,
        environment: environment,
      ),
      stdinText: stdinText,
      timeout: timeout,
    );
    if (!allowFailure && (result.timedOut || result.exitCode != 0)) {
      throw StateError(
        'git ${args.join(' ')} failed (${result.exitCode}): ${result.stderr}',
      );
    }
    return GitRawResult(
      exitCode: result.exitCode,
      stdout: result.stdout,
      stderr: result.stderr,
    );
  }

  @override
  Future<void> runToFile(
    List<String> args,
    String destPath, {
    String? workingDirectory,
    Map<String, String>? environment,
    Duration? timeout,
  }) async {
    final base = HostShellArgv.command(executable: _git, arguments: args);
    final script = '$base > ${RemoteFileStore.shellSingleQuote(destPath)}';
    final result = await _runWslProcess(
      _wslArgv(
        executable: 'sh',
        arguments: ['-c', script],
        workingDirectory: workingDirectory,
        environment: environment,
      ),
      timeout: timeout,
    );
    if (result.timedOut || result.exitCode != 0) {
      throw StateError(
        'git ${args.join(' ')} redirect failed '
        '(${result.exitCode}): ${result.stderr}',
      );
    }
  }

  @override
  Future<GitCommandResult> runScript(
    String script, {
    String? workingDirectory,
    Map<String, String>? environment,
    String? stdinText,
    Duration? timeout,
  }) async {
    final result = await _runWslProcess(
      _wslArgv(
        executable: 'sh',
        arguments: ['-c', script],
        workingDirectory: workingDirectory,
        environment: environment,
      ),
      stdinText: stdinText,
      timeout: timeout,
    );
    return GitCommandResult(
      exitCode: result.exitCode,
      stdout: utf8.decode(result.stdout, allowMalformed: true),
      stderr: result.stderr,
    );
  }

  @override
  Future<GitCapability> probe() async =>
      gitCapabilityFromVersion(await runRaw(['--version'], allowFailure: true));

  @override
  Future<GitCommandResult> runInDirectory(
    String dir,
    List<String> args, {
    Map<String, String>? environment,
  }) async {
    final result = await _host.run(
      HostRunRequest(
        executable: _git,
        arguments: _gitArgv(dir, args),
        environment: environment,
      ),
    );
    return _gitResultFromHost(result);
  }
}

class RemoteGitCommandRunner implements GitCommandRunner {
  RemoteGitCommandRunner({
    RemoteFileStore? store,
    Future<SSHRunResult> Function(String command)? execShell,
    Future<SSHRunResult> Function(String command, List<int> stdin)?
        execShellWithStdin,
    HostOneShotRunner? hostRunner,
    String? hostKey,
    String? gitExecutable,
  }) : assert(
         store != null || execShell != null,
         'store or execShell required',
       ),
       _execShell = execShell ?? store!.execShell,
       _execShellWithStdin =
           execShellWithStdin ?? store?.execShellWithStdin,
       _hostKey = hostKey ?? '',
       _exe = _resolvedConfiguredGit(gitExecutable),
       _host =
           hostRunner ??
           RemoteHostOneShotRunner(execShell: execShell ?? store!.execShell);

  final Future<SSHRunResult> Function(String command) _execShell;
  final Future<SSHRunResult> Function(String command, List<int> stdin)?
      _execShellWithStdin;
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
    // Probe over stdout, not exit status: SSH servers may omit exit status
    // (sshRunSucceeded treats null as success), so a silent probe cannot
    // distinguish installed from missing. Slash-paths must pass `test -x`
    // because `command -v` echoes non-executable paths.
    final probe = _exe != null
        ? "test -x '$exe' && printf '%s\\n' x || "
              "{ case '$exe' in */*) exit 1;; *) command -v '$exe' 2>/dev/null;; esac; }"
        : 'command -v git 2>/dev/null || which git 2>/dev/null';
    final result = await _execShell(probe);
    if (sshRunFailed(result)) return false;
    return utf8.decode(result.stdout, allowMalformed: true).trim().isNotEmpty;
  }

  @override
  Future<GitRawResult> runRaw(
    List<String> args, {
    String? workingDirectory,
    Map<String, String>? environment,
    String? stdinText,
    bool allowFailure = false,
    Duration? timeout,
  }) async {
    final command = HostShellArgv.command(
      executable: _git,
      arguments: args,
      workingDirectory: workingDirectory,
      environment: environment,
    );
    final SSHRunResult result;
    if (stdinText == null) {
      result = await _execShell(command);
    } else {
      final exec = _execShellWithStdin;
      if (exec == null) throw StateError('stdin exec not configured');
      result = await exec(command, utf8.encode(stdinText));
    }
    final exit = result.exitCode ?? (sshRunSucceeded(result) ? 0 : 1);
    final raw = GitRawResult(
      exitCode: exit,
      stdout: result.stdout,
      stderr: utf8.decode(result.stderr, allowMalformed: true),
    );
    if (!allowFailure && exit != 0) {
      throw StateError('git ${args.join(' ')} failed ($exit): ${raw.stderr}');
    }
    return raw;
  }

  @override
  Future<void> runToFile(
    List<String> args,
    String destPath, {
    String? workingDirectory,
    Map<String, String>? environment,
    Duration? timeout,
  }) async {
    final base = HostShellArgv.command(
      executable: _git,
      arguments: args,
      workingDirectory: workingDirectory,
      environment: environment,
    );
    final result = await _execShell(
      '$base > ${RemoteFileStore.shellSingleQuote(destPath)}',
    );
    if (sshRunFailed(result)) {
      throw StateError('git ${args.join(' ')} redirect failed');
    }
  }

  @override
  Future<GitCommandResult> runScript(
    String script, {
    String? workingDirectory,
    Map<String, String>? environment,
    String? stdinText,
    Duration? timeout,
  }) async {
    final prefix = HostShellArgv.command(
      executable: 'sh',
      arguments: ['-c', script],
      workingDirectory: workingDirectory,
      environment: environment,
    );
    final result = stdinText == null
        ? await _execShell(prefix)
        : await _execShellWithStdin!(prefix, utf8.encode(stdinText));
    return GitCommandResult(
      exitCode: result.exitCode ?? (sshRunSucceeded(result) ? 0 : 1),
      stdout: utf8.decode(result.stdout, allowMalformed: true),
      stderr: utf8.decode(result.stderr, allowMalformed: true),
    );
  }

  @override
  Future<GitCapability> probe() async =>
      gitCapabilityFromVersion(await runRaw(['--version'], allowFailure: true));

  @override
  Future<GitCommandResult> runInDirectory(
    String dir,
    List<String> args, {
    Map<String, String>? environment,
  }) async {
    final result = await _host.run(
      HostRunRequest(
        executable: _git,
        arguments: _gitArgv(dir, args),
        environment: environment,
      ),
    );
    return _gitResultFromHost(result);
  }
}
