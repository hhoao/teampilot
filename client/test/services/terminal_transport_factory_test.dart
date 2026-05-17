import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/launch_target.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/ssh_known_host_repository.dart';
import 'package:teampilot/repositories/ssh_profile_repository.dart';
import 'package:teampilot/services/ssh_client_factory.dart';
import 'package:teampilot/services/terminal_transport.dart';
import 'package:teampilot/services/terminal_transport_factory.dart';

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
              required SshProfile profile,
              required SshClientFactory clientFactory,
              required String command,
              required int columns,
              required int rows,
            }) async {
              startedProfile = profile;
              startedCommand = command;
              return _FakeTransport();
            },
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
