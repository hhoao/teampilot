import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';

import 'host_one_shot_runner.dart';

export 'host_run_request.dart';
export 'host_run_result.dart';
export 'host_shell_argv.dart';
export 'host_wsl_argv.dart';

typedef HostProcessRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
      Map<String, String>? environment,
      bool includeParentEnvironment,
      Encoding? stdoutEncoding,
      Encoding? stderrEncoding,
    });

/// Runs a short-lived command on native disk, WSL, or SSH.
abstract interface class HostOneShotRunner {
  Future<HostRunResult> run(HostRunRequest request);
}

class LocalHostOneShotRunner implements HostOneShotRunner {
  LocalHostOneShotRunner({HostProcessRunner? processRunner})
    : _processRunner = processRunner ?? _defaultProcessRunner;

  final HostProcessRunner _processRunner;

  static const Encoding _textEncoding = Utf8Codec(allowMalformed: true);

  static Future<ProcessResult> _defaultProcessRunner(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    Encoding? stdoutEncoding,
    Encoding? stderrEncoding,
  }) {
    return Process.run(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      includeParentEnvironment: includeParentEnvironment,
      stdoutEncoding: stdoutEncoding ?? _textEncoding,
      stderrEncoding: stderrEncoding ?? _textEncoding,
    );
  }

  @override
  Future<HostRunResult> run(HostRunRequest request) async {
    final result = await _processRunner(
      request.executable,
      request.arguments,
      workingDirectory: request.workingDirectory,
      environment: request.environment,
      includeParentEnvironment: request.includeParentEnvironment,
    );
    return HostRunResult.fromProcess(result);
  }
}

class WslHostOneShotRunner implements HostOneShotRunner {
  WslHostOneShotRunner({
    String? distro,
    HostProcessRunner? processRunner,
  }) : _distro = distro?.trim(),
       _processRunner = processRunner ?? LocalHostOneShotRunner._defaultProcessRunner;

  final String? _distro;
  final HostProcessRunner _processRunner;

  @override
  Future<HostRunResult> run(HostRunRequest request) async {
    final args = HostWslArgv.processInvocation(
      distro: _distro,
      workingDirectory: request.workingDirectory,
      executable: request.executable,
      arguments: request.arguments,
    );
    final result = await _processRunner(
      'wsl.exe',
      args,
      includeParentEnvironment: request.includeParentEnvironment,
    );
    return HostRunResult.fromProcess(result);
  }
}

class RemoteHostOneShotRunner implements HostOneShotRunner {
  RemoteHostOneShotRunner({
    required Future<SSHRunResult> Function(String command) execShell,
  }) : _execShell = execShell;

  final Future<SSHRunResult> Function(String command) _execShell;

  @override
  Future<HostRunResult> run(HostRunRequest request) async {
    final command = HostShellArgv.command(
      executable: request.executable,
      arguments: request.arguments,
      workingDirectory: request.workingDirectory,
      environment: request.environment,
    );
    final result = await _execShell(command);
    return HostRunResult.fromSsh(result);
  }
}
