import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/launch_target.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/ssh_known_host_repository.dart';
import 'package:teampilot/repositories/ssh_profile_repository.dart';
import 'package:teampilot/services/ssh/ssh_member_session.dart';
import 'package:teampilot/services/ssh/ssh_client_factory.dart';
import 'package:teampilot/services/terminal/terminal_transport.dart';
import 'package:teampilot/services/terminal/terminal_transport_factory.dart';

class _FakeTransport implements TerminalTransport {
  final doneCompleter = Completer<int>();

  @override
  Future<int> get done => doneCompleter.future;

  @override
  Stream<Uint8List> get output => const Stream.empty();

  @override
  void close() {
    if (!doneCompleter.isCompleted) {
      doneCompleter.complete(0);
    }
  }

  @override
  void resize(int rows, int columns) {}

  @override
  void write(Uint8List data) {}
}

class _InstantAuthClient extends SSHClient {
  _InstantAuthClient() : super(_FakeSSHSocket(), username: 'test');

  @override
  Future<void> get authenticated => Future.value();
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
  Future<void> get done async {}
}

void main() {
  test(
    'SSH launch target resolves profile and builds remote command',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'terminal_transport_factory_test_',
      );
      addTearDown(() => temp.delete(recursive: true));
      final profileRepository = SshProfileRepository(rootDir: temp.path);
      final profile = SshProfile(
        id: 'p1',
        name: 'dev',
        host: 'example.com',
        username: 'alice',
      );
      await profileRepository.save(profile);

      SshProfile? startedProfile;
      String? startedCommand;
      final factory = TerminalTransportFactory(
        sshProfileRepository: profileRepository,
        sshCredentialStore: InMemorySshCredentialStore(),
        sshKnownHostRepository: InMemorySshKnownHostRepository(),
        sshStarter:
            ({
              required SshMemberSession memberSession,
              required String command,
              required int columns,
              required int rows,
            }) async {
              startedProfile = memberSession.profile;
              startedCommand = command;
              return _FakeTransport();
            },
      );

      final memberSession = SshMemberSession.testing(
        profile: profile,
        client: _InstantAuthClient(),
      );

      await factory.startTransport(
        const LaunchTarget.ssh(
          sshProfileId: 'p1',
          remoteExecutable: 'flashskyai',
          remoteWorkingDirectory: '~/repo',
          remoteEnvironment: {'LLM_CONFIG_PATH': '~/.flashskyai/llm.json'},
          useLoginShell: true,
        ),
        arguments: const ['--resume', 's1'],
        columns: 80,
        rows: 24,
        memberSession: memberSession,
      );

      expect(startedProfile, profile);
      expect(
        startedCommand,
        startsWith(r'TERM="${TERM:-xterm-256color}" bash -lc '),
      );
      expect(startedCommand, contains('~/repo'));
      expect(startedCommand, contains('--resume'));
      expect(startedCommand, contains('s1'));
      expect(startedCommand, contains('LLM_CONFIG_PATH'));
      expect(startedCommand, isNot(contains('REMOTE_ONLY')));
    },
  );
}
