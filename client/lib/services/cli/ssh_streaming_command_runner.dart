import 'dart:async';
import 'dart:convert';

import '../../models/ssh_profile.dart';
import '../host/process_run_handle.dart';
import '../ssh/ssh_storage_io.dart';
import 'installer_types.dart';

typedef SshProcessStarter =
    Future<ProcessRunHandle> Function(SshProfile profile, String command);

final class SshStreamingCommandRunner {
  SshStreamingCommandRunner({
    required SshProcessStarter startProcess,
    this.timeout = SshStorageIo.provisionPhaseTimeout,
    this.maxCapturedChars = 1 << 20,
  }) : _startProcess = startProcess;

  final SshProcessStarter _startProcess;
  final Duration timeout;
  final int maxCapturedChars;

  Future<CliInstallerCommandResult> run(
    SshProfile profile,
    CliInstallerCommand command, {
    void Function(String line)? onOutput,
  }) async {
    ProcessRunHandle handle;
    try {
      handle = await _startProcess(profile, command.commandLine);
    } on Object catch (error) {
      return CliInstallerCommandResult(exitCode: 1, stderr: error.toString());
    }

    final stdoutTail = _TailBuffer(maxCapturedChars);
    final stderrTail = _TailBuffer(maxCapturedChars);

    Future<void> drain(Stream<List<int>> stream, _TailBuffer tail) async {
      // Legacy-locale hosts emit non-UTF-8 bytes; decode leniently (as the
      // one-shot path and `git_installer.dart` do) instead of failing the
      // whole install on a single bad byte.
      await stream
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .forEach((line) {
            tail.add(line);
            try {
              onOutput?.call(line);
            } on Object {
              // A throwing log sink must not abort the drain or the command.
            }
          });
    }

    try {
      final exitCode = await () async {
        await Future.wait([
          drain(handle.stdout, stdoutTail),
          drain(handle.stderr, stderrTail),
        ]);
        return handle.exitCode;
      }().timeout(timeout);

      return CliInstallerCommandResult(
        exitCode: exitCode,
        stdout: stdoutTail.text,
        stderr: stderrTail.text,
      );
    } on TimeoutException {
      handle.kill();
      return CliInstallerCommandResult(
        exitCode: 124,
        stdout: stdoutTail.text,
        stderr: 'timed out',
      );
    } on Object catch (error) {
      handle.kill();
      return CliInstallerCommandResult(exitCode: 1, stderr: error.toString());
    }
  }
}

final class _TailBuffer {
  _TailBuffer(this.maxChars);

  final int maxChars;
  final List<String> _lines = <String>[];
  int _chars = 0;

  void add(String line) {
    _lines.add(line);
    _chars += line.length + 1;
    while (_chars > maxChars && _lines.length > 1) {
      _chars -= _lines.removeAt(0).length + 1;
    }
  }

  String get text => _lines.join('\n');
}
