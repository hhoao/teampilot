import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../models/ssh_profile.dart';
import '../../models/team_config.dart';
import 'cli_tool_locator.dart';
import 'installer_types.dart';
import 'registry/capabilities/installer_capability.dart';
import 'registry/cli_tool_registry.dart';
import 'registry/installer/installer_context.dart';
import 'registry/installer/teampilot_node_install.dart';
import '../host/host_execution_environment.dart';
import '../host/host_login_shell_lookup.dart';
import '../host/host_script_runner.dart';
import '../host/macos_npm_path_candidates.dart';
import '../storage/runtime_context.dart';
import '../storage/app_storage.dart';
import '../ssh/ssh_client_factory.dart';

export 'installer_types.dart';

class CliInstallerService {
  CliInstallerService({
    LocalCliInstallRunner? localRunner,
    SshCliInstallRunner? sshRunner,
    SshClientFactory? sshClientFactory,
    bool? isWindowsOverride,
    HostExecutionEnvironment? hostEnvironment,
    CliToolRegistry? cliToolRegistry,
  }) : _localRunner = localRunner ?? _runLocal,
       _sshRunner = sshRunner ?? _SshCommandRunner(sshClientFactory).run,
       _hostEnvironment =
           hostEnvironment ??
           (AppStorage.isInstalled
               ? HostExecutionEnvironment.fromStorage(
                   AppStorage.context,
                 )
               : HostExecutionEnvironment.resolve(
                   isWindowsHost: isWindowsOverride ?? Platform.isWindows,
                 )),
       _cliToolRegistry = cliToolRegistry ?? _defaultCliRegistry;

  static final _defaultCliRegistry = () {
    final r = CliToolRegistry.builtIn();
    return r;
  }();

  final LocalCliInstallRunner _localRunner;
  final SshCliInstallRunner _sshRunner;
  final HostExecutionEnvironment _hostEnvironment;
  final CliToolRegistry _cliToolRegistry;
  CliInstallProgressCallback? _onProgress;

  Future<CliInstallResult> install({
    required CliTool cli,
    required CliInstallMode mode,
    SshProfile? sshProfile,
    CliInstallProgressCallback? onProgress,
  }) async {
    final capability =
        _cliToolRegistry.capability<InstallerCapability>(cli);
    if (capability == null || !capability.supportsInstaller) {
      return const CliInstallResult(
        success: false,
        message: 'In-app installation is not supported for this CLI.',
      );
    }

    _onProgress = onProgress;
    try {
      return await capability.install(
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
        streamOutput && _onProgress != null && identical(_localRunner, _runLocal);
    if (useStreaming) {
      return _runLocalStreaming(
        command,
        onOutput: (line) => _report(phase, detail: line),
      );
    }
    return _localRunner(command);
  }

  Future<String?> _locateLocalNpm() async {
    return const CliToolLocator('npm').locate(
      runner: (executable, arguments, {stdoutEncoding, stderrEncoding}) async {
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
    ).then((located) {
      if (located != null) return located;
      if (!identical(_localRunner, _runLocal)) return null;
      return MacOsNpmPathCandidates.firstExisting();
    });
  }

  Future<String?> _locateRemoteNpm(SshProfile profile) async {
    final npmLookup = HostLoginShellLookup.commandForExecutable('npm');
    final direct = await _sshRunner(
      profile,
      CliInstallerCommand.commandV('npm'),
    );
    final fromDirect = firstInstallerOutputLine(direct);
    if (fromDirect != null) return fromDirect;

    return HostLoginShellLookup.locateViaLoginShells(
      innerCommand: npmLookup,
      runner: (executable, arguments, {stdoutEncoding, stderrEncoding}) async {
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
  }

  Future<String?> _locateLocalExecutable(String name) {
    return CliToolLocator(name).locate(
      runner: (executable, arguments, {stdoutEncoding, stderrEncoding}) async {
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
  }) async {
    try {
      final process = await Process.start(
        command.executable,
        command.arguments,
      );
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
  }) =>
      _service._runLocalTracked(
        command,
        phase: phase,
        streamOutput: streamOutput,
      );

  @override
  Future<CliInstallerCommandResult> runSsh(
    SshProfile profile,
    CliInstallerCommand command,
  ) =>
      _service._sshRunner(profile, command);

  @override
  Future<String?> locateExecutable(String name) =>
      _service._locateLocalExecutable(name);

  @override
  Future<String?> locateLocalNpm() => _service._locateLocalNpm();

  @override
  Future<String?> locateRemoteNpm(SshProfile profile) =>
      _service._locateRemoteNpm(profile);
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
      final client = await factory.clientForStorage(profile);
      final session = await client.execute(command.commandLine);
      final stdout = await _decode(session.stdout);
      final stderr = await _decode(session.stderr);
      await session.done;
      return CliInstallerCommandResult(
        exitCode: session.exitCode ?? 0,
        stdout: stdout,
        stderr: stderr,
      );
    } on Object catch (e) {
      return CliInstallerCommandResult(exitCode: 1, stderr: e.toString());
    }
  }

  static Future<String> _decode(Stream<Uint8List> stream) async {
    return utf8.decode(await stream.fold<List<int>>(
      <int>[],
      (buffer, chunk) => buffer..addAll(chunk),
    ));
  }
}
