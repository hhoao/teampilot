import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/services/cli/installer_types.dart';
import 'package:teampilot/services/cli/remote_install_task.dart';
import 'package:teampilot/services/ssh/ssh_client_factory.dart';
import 'package:teampilot/services/ssh/worker/ssh_worker_member_session.dart';
import 'package:teampilot/services/ssh/worker/ssh_worker_storage_types.dart';

const _profile = SshProfile(
  id: 'p1',
  name: 'box',
  host: 'example.com',
  port: 22,
  username: 'dev',
);

void main() {
  test('runner decodes member exec output', () async {
    final transport = _FakeMemberTransport(
      (command) async => SshWorkerRunResult(
        stdout: Uint8List.fromList('done\n'.codeUnits),
        stderr: Uint8List(0),
        exitCode: 0,
      ),
    );
    final task = await RemoteInstallTask.open(
      _FakeFactory(transport),
      _profile,
    );
    addTearDown(task.close);

    final result = await task.runner('echo done');

    expect(result.exitCode, 0);
    expect(result.stdout, 'done\n');
    expect(result.stderr, isEmpty);
  });

  test('a command budget closes only the task channel', () async {
    final transport = _FakeMemberTransport(
      (command) => Completer<SshWorkerRunResult>().future,
    );
    final task = await RemoteInstallTask.open(
      _FakeFactory(transport),
      _profile,
      commandTimeout: const Duration(milliseconds: 10),
    );
    addTearDown(task.close);

    await expectLater(
      task.runner('sleep 600'),
      throwsA(isA<TimeoutException>()),
    );
    expect(transport.closed, 1);
  });

  test('a wedged worker open is bounded client-side', () async {
    final transport = _FakeMemberTransport(
      (command) async =>
          SshWorkerRunResult(stdout: Uint8List(0), stderr: Uint8List(0)),
      onOpen: () => Completer<void>().future,
    );

    await expectLater(
      RemoteInstallTask.open(
        _FakeFactory(transport),
        _profile,
        connectTimeout: const Duration(milliseconds: 20),
      ),
      throwsA(isA<TimeoutException>()),
    );
    expect(transport.closed, 1);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('streamed install forwards member exec lines and exit code', () async {
    final channel = _FakeExecChannel(
      stdout: Stream.fromIterable([
        Uint8List.fromList('one\ntw'.codeUnits),
        Uint8List.fromList('o\n'.codeUnits),
      ]),
      stderr: const Stream<Never>.empty(),
      done: Future.value(0),
    );
    final transport = _FakeMemberTransport(
      (command) async =>
          SshWorkerRunResult(stdout: Uint8List(0), stderr: Uint8List(0)),
      onStartProcess: (_) async => channel,
    );
    final task = await RemoteInstallTask.open(
      _FakeFactory(transport),
      _profile,
    );
    addTearDown(task.close);

    final lines = <String>[];
    final result = await installStreamingRunnerForRemoteTask(task)(
      _profile,
      CliInstallerCommand('npm', ['install']),
      onOutput: lines.add,
    );

    expect(result.stderr, isEmpty);
    expect(lines, ['one', 'two']);
    expect(result.exitCode, 0);
    expect(result.stdout, 'one\ntwo');
  });

  test(
    'a timed-out streamed command kills the exec and closes the task',
    () async {
      final channel = _FakeExecChannel(
        stdout: StreamController<Uint8List>().stream,
        stderr: StreamController<Uint8List>().stream,
        done: Completer<int>().future,
      );
      final transport = _FakeMemberTransport(
        (command) async =>
            SshWorkerRunResult(stdout: Uint8List(0), stderr: Uint8List(0)),
        onStartProcess: (_) async => channel,
      );
      final task = await RemoteInstallTask.open(
        _FakeFactory(transport),
        _profile,
        commandTimeout: const Duration(milliseconds: 20),
      );
      addTearDown(task.close);

      final result = await installStreamingRunnerForRemoteTask(task)(
        _profile,
        CliInstallerCommand('npm', ['install']),
      );

      expect(result.exitCode, 124);
      expect(channel.killed, 1);
      await Future<void>.delayed(Duration.zero);
      expect(transport.closed, 1);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}

final class _FakeFactory implements SshClientFactory {
  _FakeFactory(this.transport);
  final SshWorkerMemberTransport transport;

  @override
  Future<SshWorkerMemberTransport> openMemberTransport(
    SshProfile profile, {
    Duration timeout = const Duration(seconds: 10),
  }) async => transport;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _FakeMemberTransport implements SshWorkerMemberTransport {
  _FakeMemberTransport(this._onRun, {this.onOpen, this.onStartProcess});
  final Future<SshWorkerRunResult> Function(String command) _onRun;
  final Future<void> Function()? onOpen;
  final Future<SshWorkerExecChannel> Function(String command)? onStartProcess;
  var closed = 0;

  @override
  Future<void> open(
    SshProfile profile, {
    Duration timeout = const Duration(seconds: 10),
  }) => onOpen?.call() ?? Future.value();

  @override
  Future<SshWorkerRunResult> run(String command, {bool stderr = true}) =>
      _onRun(command);

  @override
  Future<SshWorkerExecChannel> startProcess(String command) {
    final start = onStartProcess;
    if (start == null) throw UnimplementedError();
    return start(command);
  }

  @override
  Future<SshWorkerPtyChannel> openPty({
    String? command,
    required int columns,
    required int rows,
    Map<String, String>? environment,
  }) => throw UnimplementedError();

  @override
  Future<void> close() async => closed++;
}

final class _FakeExecChannel implements SshWorkerExecChannel {
  _FakeExecChannel({
    required this.stdout,
    required this.stderr,
    required this.done,
  });

  @override
  final Stream<Uint8List> stdout;

  @override
  final Stream<Uint8List> stderr;

  @override
  final Future<int> done;

  var killed = 0;

  @override
  void kill() => killed++;

  @override
  void write(Uint8List data) {}

  @override
  void closeStdin() {}

  @override
  void close() {}
}
