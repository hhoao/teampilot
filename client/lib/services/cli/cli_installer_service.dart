import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../models/ssh_profile.dart';
import '../../models/team_config.dart';
import 'cli_tool_locator.dart';
import 'installer_types.dart';
import 'registry/capabilities/cli_executable_capability.dart';
import 'registry/cli_tool_registry.dart';
import 'registry/installer/acp_adapter_installer.dart';
import 'registry/installer/installer_context.dart';
import 'registry/installer/teampilot_node_install.dart';
import 'registry/installer/termux_remote_detect.dart';
import 'remote_install_task.dart';
import '../host/host_executable_locator.dart';
import '../host/host_execution_environment.dart';
import '../host/host_login_shell_lookup.dart';
import '../host/host_script_runner.dart';
import '../host/macos_npm_path_candidates.dart';
import '../ssh/ssh_client_factory.dart';
import 'ssh_streaming_command_runner.dart';

export 'installer_types.dart';

typedef CliInstallOutputLine = void Function(String line);

class CliInstallerService {
  CliInstallerService({
    LocalCliInstallRunner? localRunner,
    SshCliInstallRunner? sshRunner,
    SshClientFactory? sshClientFactory,
    SshStreamingInstallRunner? sshStreamingRunner,
    bool? isWindowsOverride,
    HostExecutionEnvironment? hostEnvironment,
    CliToolRegistry? cliToolRegistry,
    String? Function()? preferredNodePath,
  }) : _localRunner = localRunner ?? _runLocal,
       _sshRunnerOverride = sshRunner,
       _sshStreamingRunnerOverride = sshStreamingRunner,
       _sshClientFactory = sshClientFactory,
       _hostEnvironment =
           hostEnvironment ??
           HostExecutionEnvironment.resolve(
             isWindowsHost: isWindowsOverride ?? Platform.isWindows,
           ),
       _cliToolRegistry = cliToolRegistry ?? _defaultCliRegistry,
       _preferredNodePath = preferredNodePath;

  static final _defaultCliRegistry = () {
    final r = CliToolRegistry.builtIn();
    return r;
  }();

  final LocalCliInstallRunner _localRunner;
  final SshCliInstallRunner? _sshRunnerOverride;
  final SshStreamingInstallRunner? _sshStreamingRunnerOverride;
  final SshClientFactory? _sshClientFactory;
  late SshCliInstallRunner _sshRunner =
      _sshRunnerOverride ?? _SshCommandRunner(_sshClientFactory).run;

  /// Set while a member-plane [RemoteInstallTask] is open.
  SshStreamingInstallRunner? _taskStreamingRunner;
  final HostExecutionEnvironment _hostEnvironment;
  final CliToolRegistry _cliToolRegistry;
  final String? Function()? _preferredNodePath;
  CliInstallProgressCallback? _onProgress;
  CliInstallOutputLine? _onOutputLine;
  bool Function()? _isCancelled;
  void Function(Process process)? _onProcessStarted;

  SshStreamingInstallRunner? get _resolvedStreamingRunner =>
      _sshStreamingRunnerOverride ?? _taskStreamingRunner;

  Future<CliInstallResult> install({
    required CliTool cli,
    required CliInstallMode mode,
    SshProfile? sshProfile,
    CliInstallProgressCallback? onProgress,
    CliInstallOutputLine? onOutputLine,
    bool Function()? isCancelled,
    void Function(Process process)? onProcessStarted,
  }) async {
    final capability = _cliToolRegistry.capability<CliExecutableCapability>(
      cli,
    );
    if (capability == null || !capability.supportsInstaller) {
      return const CliInstallResult(
        success: false,
        message: 'In-app installation is not supported for this CLI.',
      );
    }

    return _runInstall(
      capability.install,
      mode: mode,
      sshProfile: sshProfile,
      onProgress: onProgress,
      onOutputLine: onOutputLine,
      isCancelled: isCancelled,
      onProcessStarted: onProcessStarted,
    );
  }

  /// Installs a separate ACP adapter (npm package or standalone binary) with
  /// the same [CliInstallContext] host as [install].
  Future<CliInstallResult> installAdapter({
    required AcpAdapterInstaller installer,
    required CliInstallMode mode,
    SshProfile? sshProfile,
    CliInstallProgressCallback? onProgress,
    CliInstallOutputLine? onOutputLine,
    bool Function()? isCancelled,
    void Function(Process process)? onProcessStarted,
  }) {
    return _runInstall(
      installer.install,
      mode: mode,
      sshProfile: sshProfile,
      onProgress: onProgress,
      onOutputLine: onOutputLine,
      isCancelled: isCancelled,
      onProcessStarted: onProcessStarted,
    );
  }

  Future<CliInstallResult> _runInstall(
    Future<CliInstallResult> Function(CliInstallContext context) install, {
    required CliInstallMode mode,
    SshProfile? sshProfile,
    CliInstallProgressCallback? onProgress,
    CliInstallOutputLine? onOutputLine,
    bool Function()? isCancelled,
    void Function(Process process)? onProcessStarted,
  }) async {
    _onProgress = onProgress;
    _onOutputLine = onOutputLine;
    _isCancelled = isCancelled;
    _onProcessStarted = onProcessStarted;
    final profile = sshProfile;
    RemoteInstallTask? task;
    try {
      if (mode == CliInstallMode.ssh &&
          profile != null &&
          _sshRunnerOverride == null &&
          _sshClientFactory != null) {
        task = await RemoteInstallTask.open(_sshClientFactory, profile);
        _sshRunner = installRunnerForRemoteTask(task);
        _taskStreamingRunner = installStreamingRunnerForRemoteTask(task);
      }
      return await install(
        CliInstallContext(
          mode: mode,
          host: _CliInstallerHost(this),
          hostEnvironment: _hostEnvironment,
          sshProfile: sshProfile,
          node: TeampilotNodeInstall.standard,
        ),
      );
    } finally {
      _onProgress = null;
      _onOutputLine = null;
      _isCancelled = null;
      _onProcessStarted = null;
      if (task != null) {
        _taskStreamingRunner = null;
        _sshRunner = _SshCommandRunner(_sshClientFactory).run;
        await task.close();
      }
    }
  }

  void _report(CliInstallPhase phase, {String? detail}) {
    _onProgress?.call(CliInstallProgress(phase: phase, detail: detail));
  }

  Future<CliInstallerCommandResult> _runLocalTracked(
    CliInstallerCommand command, {
    required CliInstallPhase phase,
    bool streamOutput = false,
  }) async {
    _report(phase);
    final useStreaming =
        (streamOutput || _onOutputLine != null) &&
        identical(_localRunner, _runLocal);
    if (useStreaming) {
      return _runLocalStreaming(
        command,
        onOutput: (line) {
          if (streamOutput) _report(phase, detail: line);
          _onOutputLine?.call(line);
        },
        onProcessStarted: _onProcessStarted,
      );
    }
    return _localRunner(command);
  }

  Future<String?> _locateLocalNpm() async {
    final fromPreferred = await _locateSiblingNpmLocal();
    if (fromPreferred != null) return fromPreferred;

    return const CliToolLocator('npm')
        .locate(
          runner:
              (
                executable,
                arguments, {
                environment,
                stdoutEncoding,
                stderrEncoding,
              }) async {
                final result = await _localRunner(
                  CliInstallerCommand(executable, arguments),
                );
                return ProcessResult(
                  -1,
                  result.exitCode,
                  result.stdout,
                  result.stderr,
                );
              },
          isWindowsOverride: _hostEnvironment.isWindowsHost,
        )
        .then((located) {
          if (located != null) return located;
          if (!identical(_localRunner, _runLocal)) return null;
          return MacOsNpmPathCandidates.firstExisting();
        });
  }

  Future<String?> _locateRemoteNpm(SshProfile profile) async {
    final fromPreferred = await _locateSiblingNpmRemote(profile);
    if (fromPreferred != null) return fromPreferred;

    final npmLookup = HostLoginShellLookup.commandForExecutable('npm');
    final direct = await _sshRunner(
      profile,
      CliInstallerCommand.commandV('npm'),
    );
    final fromDirect = firstInstallerOutputLine(direct);
    if (fromDirect != null) return fromDirect;

    final fromLogin = await HostLoginShellLookup.locateViaLoginShells(
      innerCommand: npmLookup,
      runner:
          (
            executable,
            arguments, {
            environment,
            stdoutEncoding,
            stderrEncoding,
          }) async {
            final result = await _sshRunner(
              profile,
              CliInstallerCommand(executable, arguments),
            );
            return ProcessResult(
              -1,
              result.exitCode,
              result.stdout,
              result.stderr,
            );
          },
    );
    if (fromLogin != null) return fromLogin;

    // Termux SSH sessions often omit $PREFIX/bin from non-login PATH.
    final prefixAware = await _sshRunner(
      profile,
      CliInstallerCommand.unixShellScript(
        '${TermuxRemoteDetect.exportPrefixPathShell}\n'
        'command -v npm',
      ),
    );
    return firstInstallerOutputLine(prefixAware);
  }

  Future<String?> _locateLocalExecutable(String name) async {
    if (name == 'node') {
      final preferred = _preferredNodePath?.call()?.trim() ?? '';
      if (preferred.isNotEmpty) {
        final probed = await _probeLocalExecutablePath(preferred);
        if (probed != null) return probed;
      }
    }
    return CliToolLocator(name).locate(
      runner:
          (
            executable,
            arguments, {
            environment,
            stdoutEncoding,
            stderrEncoding,
          }) async {
            final result = await _localRunner(
              CliInstallerCommand(executable, arguments),
            );
            return ProcessResult(
              -1,
              result.exitCode,
              result.stdout,
              result.stderr,
            );
          },
      isWindowsOverride: _hostEnvironment.isWindowsHost,
    );
  }

  String? _configuredNodePath() {
    final node = _preferredNodePath?.call()?.trim() ?? '';
    return node.isEmpty ? null : node;
  }

  Iterable<String> _siblingNpmCandidates(String nodePath) sync* {
    // Match [HostExecutionEnvironment.isWindowsHost], not [p.context], so
    // Unix-override installs on a Windows CI host still join POSIX siblings.
    final ctx = _hostEnvironment.isWindowsHost ? p.windows : p.posix;
    final dir = ctx.dirname(nodePath);
    if (_hostEnvironment.isWindowsHost) {
      yield ctx.join(dir, 'npm.cmd');
      yield ctx.join(dir, 'npm');
    } else {
      yield ctx.join(dir, 'npm');
    }
  }

  Future<String?> _locateSiblingNpmLocal() async {
    final node = _configuredNodePath();
    if (node == null) return null;
    for (final candidate in _siblingNpmCandidates(node)) {
      final found = await _probeLocalExecutablePath(candidate);
      if (found != null) return found;
    }
    return null;
  }

  Future<String?> _locateSiblingNpmRemote(SshProfile profile) async {
    final node = _configuredNodePath();
    if (node == null) return null;
    for (final candidate in _siblingNpmCandidates(node)) {
      final found = await _probeRemoteExecutablePath(profile, candidate);
      if (found != null) return found;
    }
    return null;
  }

  Future<String?> _probeLocalExecutablePath(String candidate) async {
    if (_hostEnvironment.isWindowsHost) {
      final result = await _localRunner(
        CliInstallerCommand('where', [candidate]),
      );
      if (result.exitCode != 0) return null;
      return HostExecutableLocator.parsePathLookupOutput(
            result.stdout,
            isWindows: true,
          ) ??
          candidate;
    }

    final whichResult = await _localRunner(
      CliInstallerCommand('which', [candidate]),
    );
    if (whichResult.exitCode == 0) {
      return HostExecutableLocator.parseFirstStdoutLine(whichResult.stdout) ??
          candidate;
    }

    final testResult = await _localRunner(
      CliInstallerCommand.unixShellScript('test -x ${_shellQuote(candidate)}'),
    );
    return testResult.exitCode == 0 ? candidate : null;
  }

  Future<String?> _probeRemoteExecutablePath(
    SshProfile profile,
    String candidate,
  ) async {
    final result = await _sshRunner(
      profile,
      CliInstallerCommand.unixShellScript('test -x ${_shellQuote(candidate)}'),
    );
    return result.exitCode == 0 ? candidate : null;
  }

  static String _shellQuote(String value) =>
      "'${value.replaceAll("'", "'\"'\"'")}'";

  static Future<CliInstallerCommandResult> _runLocal(
    CliInstallerCommand command,
  ) async {
    try {
      final result = await Process.run(command.executable, command.arguments);
      return CliInstallerCommandResult(
        exitCode: result.exitCode,
        stdout: result.stdout?.toString() ?? '',
        stderr: result.stderr?.toString() ?? '',
      );
    } on ProcessException catch (e) {
      return CliInstallerCommandResult(exitCode: 127, stderr: e.message);
    }
  }

  static Future<CliInstallerCommandResult> _runLocalStreaming(
    CliInstallerCommand command, {
    void Function(String line)? onOutput,
    void Function(Process process)? onProcessStarted,
  }) async {
    try {
      final process = await Process.start(
        command.executable,
        command.arguments,
      );
      onProcessStarted?.call(process);
      final stdoutBuffer = StringBuffer();
      final stderrBuffer = StringBuffer();

      Future<void> drainStream(
        Stream<List<int>> stream,
        StringBuffer buffer,
      ) async {
        await stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .forEach((line) {
              buffer.writeln(line);
              final trimmed = line.trim();
              if (trimmed.isNotEmpty) {
                onOutput?.call(trimmed);
              }
            });
      }

      await Future.wait([
        drainStream(process.stdout, stdoutBuffer),
        drainStream(process.stderr, stderrBuffer),
      ]);
      final exitCode = await process.exitCode;
      return CliInstallerCommandResult(
        exitCode: exitCode,
        stdout: stdoutBuffer.toString(),
        stderr: stderrBuffer.toString(),
      );
    } on ProcessException catch (e) {
      return CliInstallerCommandResult(exitCode: 127, stderr: e.message);
    }
  }
}

final class _CliInstallerHost implements CliInstallerHost {
  const _CliInstallerHost(this._service);

  final CliInstallerService _service;

  @override
  HostExecutionEnvironment get hostEnvironment => _service._hostEnvironment;

  @override
  bool get isWindows => hostEnvironment.isWindowsHost;

  @override
  HostScriptRunner get scriptRunner => hostEnvironment.scriptRunner;

  @override
  void report(CliInstallPhase phase, {String? detail}) =>
      _service._report(phase, detail: detail);

  @override
  Future<CliInstallerCommandResult> runLocal(
    CliInstallerCommand command, {
    required CliInstallPhase phase,
    bool streamOutput = false,
  }) => _service._runLocalTracked(
    command,
    phase: phase,
    streamOutput: streamOutput,
  );

  @override
  Future<CliInstallerCommandResult> runSsh(
    SshProfile profile,
    CliInstallerCommand command,
  ) {
    final onOutput = _service._onOutputLine;
    final streaming = _service._resolvedStreamingRunner;
    if (onOutput == null || streaming == null) {
      return _service._sshRunner(profile, command);
    }
    return streaming(profile, command, onOutput: onOutput);
  }

  @override
  Future<String?> locateExecutable(String name) =>
      _service._locateLocalExecutable(name);

  @override
  Future<String?> locateLocalNpm() => _service._locateLocalNpm();

  @override
  Future<String?> locateRemoteNpm(SshProfile profile) =>
      _service._locateRemoteNpm(profile);

  @override
  bool get isCancelled => _service._isCancelled?.call() ?? false;
}

class _SshCommandRunner {
  const _SshCommandRunner(this._clientFactory);

  final SshClientFactory? _clientFactory;

  Future<CliInstallerCommandResult> run(
    SshProfile profile,
    CliInstallerCommand command,
  ) async {
    final factory = _clientFactory;
    if (factory == null) {
      return const CliInstallerCommandResult(
        exitCode: 1,
        stderr: 'SSH client is not available.',
      );
    }
    try {
      final result = await factory.runOnStorage(profile, command.commandLine);
      return CliInstallerCommandResult(
        exitCode: result.exitCode ?? 0,
        stdout: utf8.decode(result.stdout, allowMalformed: true),
        stderr: utf8.decode(result.stderr, allowMalformed: true),
      );
    } on Object catch (e) {
      return CliInstallerCommandResult(exitCode: 1, stderr: e.toString());
    }
  }
}
