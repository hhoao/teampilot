import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ssh_profile.dart';
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
    final task = await RemoteInstallTask.open(_FakeFactory(transport), _profile);
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
  _FakeMemberTransport(this._onRun);
  final Future<SshWorkerRunResult> Function(String command) _onRun;
  var closed = 0;

  @override
  Future<void> open(
    SshProfile profile, {
    Duration timeout = const Duration(seconds: 10),
  }) async {}

  @override
  Future<SshWorkerRunResult> run(String command, {bool stderr = true}) =>
      _onRun(command);

  @override
  Future<SshWorkerExecChannel> startProcess(String command) =>
      throw UnimplementedError();

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
