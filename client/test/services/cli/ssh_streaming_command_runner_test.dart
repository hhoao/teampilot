import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/services/cli/installer_types.dart';
import 'package:teampilot/services/cli/ssh_streaming_command_runner.dart';
import 'package:teampilot/services/host/process_run_handle.dart';

final class _FakeHandle implements ProcessRunHandle {
  _FakeHandle({this.exit = 0, this.hang = false});

  final int exit;
  final bool hang;
  final stdoutController = StreamController<List<int>>();
  final stderrController = StreamController<List<int>>();
  var killed = false;

  @override
  Future<int> get exitCode =>
      hang ? Completer<int>().future : Future<int>.value(exit);

  @override
  Stream<List<int>> get stdout => stdoutController.stream;

  @override
  Stream<List<int>> get stderr => stderrController.stream;

  @override
  void kill() => killed = true;

  Future<void> close() async {
    await stdoutController.close();
    await stderrController.close();
  }
}

SshProfile _profile() => const SshProfile(
  id: 'p1',
  name: 'test',
  host: 'example.com',
  port: 22,
  username: 'u',
);

void main() {
  test('forwards stdout and stderr lines and returns the exit code', () async {
    final handle = _FakeHandle(exit: 0);
    final lines = <String>[];
    final runner = SshStreamingCommandRunner(
      startProcess: (profile, command) async => handle,
    );

    final future = runner.run(
      _profile(),
      CliInstallerCommand.unixShellScript('npm i -g x'),
      onOutput: lines.add,
    );
    handle.stdoutController.add(utf8.encode('one\ntwo\n'));
    handle.stderrController.add(utf8.encode('warn\n'));
    await handle.close();
    final result = await future;

    expect(lines, ['one', 'two', 'warn']);
    expect(result.exitCode, 0);
    expect(result.stdout, contains('two'));
    expect(result.stderr, contains('warn'));
  });

  test('kills the process and reports 124 on timeout', () async {
    final handle = _FakeHandle(hang: true);
    final runner = SshStreamingCommandRunner(
      startProcess: (profile, command) async => handle,
      timeout: const Duration(milliseconds: 20),
    );

    final future = runner.run(
      _profile(),
      CliInstallerCommand.unixShellScript('sleep 100'),
    );
    await handle.close();
    final result = await future;

    expect(handle.killed, isTrue);
    expect(result.exitCode, 124);
    expect(result.stderr, contains('timed out'));
  });

  test('captures only the tail of very large output', () async {
    final handle = _FakeHandle(exit: 0);
    final runner = SshStreamingCommandRunner(
      startProcess: (profile, command) async => handle,
      maxCapturedChars: 50,
    );

    final future = runner.run(
      _profile(),
      CliInstallerCommand.unixShellScript('yes x'),
    );
    handle.stdoutController.add(utf8.encode('${'a' * 40}\n${'b' * 40}\n'));
    await handle.close();
    final result = await future;

    expect(result.stdout.length, lessThanOrEqualTo(50));
    expect(result.stdout, contains('bbb'));
  });
}
