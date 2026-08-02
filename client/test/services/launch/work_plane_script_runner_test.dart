import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/ssh_known_host_repository.dart';
import 'package:teampilot/services/launch/work_plane_script_runner.dart';
import 'package:teampilot/services/ssh/ssh_client_factory.dart';

void main() {
  test('SshWorkPlaneScriptRunner runs script on storage plane', () async {
    String? ran;
    const profile = SshProfile(
      id: 'p1',
      name: 'dev',
      host: 'example.com',
      username: 'alice',
    );
    final factory = SshClientFactory(
      credentialStore: InMemorySshCredentialStore(),
      knownHostRepository: InMemorySshKnownHostRepository(),
      connector: (profile, {timeout = const Duration(seconds: 10)}) async {
        return _RunnableClient(
          onRun: (command) {
            ran = command;
          },
        );
      },
    );

    final runner = SshWorkPlaneScriptRunner(
      sshClientFactory: factory,
      profile: profile,
    );
    await runner.runScript('echo hi', operation: 'test-op');

    expect(ran, 'echo hi');
    expect(factory.hasLiveStorageClient(profile.id), isTrue);
  });

  test('SshWorkPlaneScriptRunner.tryCreate returns null without profile', () {
    expect(
      SshWorkPlaneScriptRunner.tryCreate(
        sshProfileId: null,
        sshClientFactory: null,
        profileById: null,
      ),
      isNull,
    );
  });

  test('SshWorkPlaneScriptRunner throws on non-zero exit', () async {
    const profile = SshProfile(
      id: 'p1',
      name: 'dev',
      host: 'example.com',
      username: 'alice',
    );
    final factory = SshClientFactory(
      credentialStore: InMemorySshCredentialStore(),
      knownHostRepository: InMemorySshKnownHostRepository(),
      connector: (profile, {timeout = const Duration(seconds: 10)}) async {
        return _RunnableClient(exitCode: 7, stderr: 'boom');
      },
    );

    final runner = SshWorkPlaneScriptRunner(
      sshClientFactory: factory,
      profile: profile,
    );
    await expectLater(
      runner.runScript('false', operation: 'cursor-home-passthrough'),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('cursor-home-passthrough'),
        ),
      ),
    );
  });
}

class _RunnableClient extends SSHClient {
  _RunnableClient({
    this.onRun,
    this.exitCode = 0,
    this.stderr = '',
  }) : super(_FakeSSHSocket(), username: 'test');

  final void Function(String command)? onRun;
  final int exitCode;
  final String stderr;

  @override
  Future<void> get authenticated => Future.value();

  @override
  Future<SSHRunResult> runWithResult(
    String command, {
    bool runInPty = false,
    bool stdout = true,
    bool stderr = true,
    Map<String, String>? environment,
  }) async {
    onRun?.call(command);
    return SSHRunResult(
      output: Uint8List(0),
      stdout: Uint8List(0),
      stderr: Uint8List.fromList(this.stderr.codeUnits),
      exitCode: exitCode,
      exitSignal: null,
    );
  }

  @override
  Future<void> ping() async {}
}

class _FakeSSHSocket implements SSHSocket {
  final _inputController = StreamController<Uint8List>();
  final _doneCompleter = Completer<void>();

  @override
  Stream<Uint8List> get stream => _inputController.stream;

  @override
  StreamSink<List<int>> get sink => _NoopSink();

  @override
  Future<void> get done => _doneCompleter.future;

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {
    if (!_doneCompleter.isCompleted) {
      _doneCompleter.complete();
    }
    await _inputController.close();
  }

  @override
  void destroy() {
    if (!_doneCompleter.isCompleted) {
      _doneCompleter.complete();
    }
    unawaited(_inputController.close());
  }
}

class _NoopSink implements StreamSink<List<int>> {
  @override
  void add(List<int> data) {}

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final _ in stream) {}
  }

  @override
  Future<void> close() async {}

  @override
  Future get done async {}
}
