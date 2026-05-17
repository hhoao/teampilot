import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/ssh_known_host_repository.dart';
import 'package:teampilot/services/remote_flashskyai_cli_locator.dart';
import 'package:teampilot/services/ssh_client_factory.dart';

void main() {
  final locator = RemoteFlashskyaiCliLocator(
    clientFactory: SshClientFactory(
      credentialStore: InMemorySshCredentialStore(),
      knownHostRepository: InMemorySshKnownHostRepository(),
    ),
  );

  test('locateWithRunner returns path from direct command -v', () async {
    final calls = <String>[];
    final located = await locator.locateWithRunner((command) async {
      calls.add(command);
      if (command == 'command -v flashskyai') {
        return const SshCommandResult(
          exitCode: 0,
          stdout: '/usr/local/bin/flashskyai\n',
        );
      }
      return const SshCommandResult(exitCode: 1, stdout: '');
    });

    expect(calls, ['command -v flashskyai']);
    expect(located, '/usr/local/bin/flashskyai');
  });

  test('locateWithRunner falls back to bash login shell', () async {
    final calls = <String>[];
    final located = await locator.locateWithRunner((command) async {
      calls.add(command);
      if (command == 'command -v flashskyai') {
        return const SshCommandResult(exitCode: 1, stdout: '');
      }
      if (command == "bash -ilc 'command -v flashskyai'") {
        return const SshCommandResult(
          exitCode: 0,
          stdout: '/home/alice/.local/bin/flashskyai\n',
        );
      }
      return const SshCommandResult(exitCode: 1, stdout: '');
    });

    expect(calls, [
      'command -v flashskyai',
      "bash -ilc 'command -v flashskyai'",
    ]);
    expect(located, '/home/alice/.local/bin/flashskyai');
  });

  test('locateWithRunner tries zsh when bash misses', () async {
    final calls = <String>[];
    final located = await locator.locateWithRunner((command) async {
      calls.add(command);
      if (command == 'command -v flashskyai') {
        return const SshCommandResult(exitCode: 1, stdout: '');
      }
      if (command == "bash -ilc 'command -v flashskyai'") {
        return const SshCommandResult(exitCode: 1, stdout: '');
      }
      if (command == "zsh -ilc 'command -v flashskyai'") {
        return const SshCommandResult(
          exitCode: 0,
          stdout: '/opt/bin/flashskyai\n',
        );
      }
      return const SshCommandResult(exitCode: 1, stdout: '');
    });

    expect(calls, [
      'command -v flashskyai',
      "bash -ilc 'command -v flashskyai'",
      "zsh -ilc 'command -v flashskyai'",
    ]);
    expect(located, '/opt/bin/flashskyai');
  });

  test('locateWithRunner returns null when every lookup fails', () async {
    final located = await locator.locateWithRunner((command) async {
      return const SshCommandResult(exitCode: 1, stdout: '');
    });

    expect(located, isNull);
  });
}
