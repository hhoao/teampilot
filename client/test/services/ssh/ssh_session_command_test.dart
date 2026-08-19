import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/flashskyai/remote_flashskyai_command_builder.dart';
import 'package:teampilot/services/terminal/ssh_pty_transport.dart';

void main() {
  test('remote command can opt into bash login environment', () {
    final command = const RemoteFlashskyaiCommandBuilder().buildCommand(
      remoteExecutablePath: 'flashskyai',
      arguments: ['--resume', 'session-123'],
      workingDirectory: '~/repo',
      useLoginShell: true,
    );

    expect(command, startsWith(r'TERM="${TERM:-xterm-256color}" bash -lc '));
    expect(command, contains(r'export TERM="${TERM:-xterm-256color}"'));
    expect(command, contains('. ~/.bashrc'));
    expect(command, contains('|| true'));
    expect(command, contains('--resume'));
    expect(command, contains('session-123'));
  });

  test('remote CLI command exposes TeamPilot Node and npm bin paths', () {
    final command = const RemoteFlashskyaiCommandBuilder().buildCommand(
      remoteExecutablePath: '/root/.local/bin/codex',
      arguments: ['plugin', 'list', '--json'],
    );

    expect(
      command,
      contains(
        r'export PATH="$HOME/.local/share/com.hhoa.teampilot/toolchain/node/current/bin:$HOME/.local/bin:$PATH"',
      ),
    );
  });

  test('SSH pty uses prebuilt command without adding a second exec', () {
    final remoteCommand = const RemoteFlashskyaiCommandBuilder().buildCommand(
      remoteExecutablePath: '/opt/flash sky/flashskyai',
      arguments: ['--session-id', "abc'123"],
      workingDirectory: '/home/me/workspace dir',
      environment: {'FLASHSKYAI_TEAM': 'core team'},
    );

    final sessionCommand = SshPtyTransport.buildSessionCommand(remoteCommand);

    expect(sessionCommand, remoteCommand);
    expect(sessionCommand, isNot(contains('exec exec')));
    expect(sessionCommand, isNot(startsWith('exec cd ')));
  });
}
