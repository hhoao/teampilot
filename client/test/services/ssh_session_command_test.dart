import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/session/remote_flashskyai_command_builder.dart';
import 'package:teampilot/services/terminal/ssh_pty_transport.dart';

void main() {
  test('remote resume command uses flashskyai resume argument shape', () {
    final command = const RemoteFlashskyaiCommandBuilder().buildResumeCommand(
      remoteExecutablePath: 'flashskyai',
      sessionId: 'session-123',
      workingDirectory: '~/repo',
    );

    expect(command, contains("'--resume' 'session-123'"));
    expect(command, isNot(contains('--session-id')));
  });

  test('remote command can opt into bash login environment', () {
    final command = const RemoteFlashskyaiCommandBuilder().buildCommand(
      remoteExecutablePath: 'flashskyai',
      arguments: ['--resume', 'session-123'],
      workingDirectory: '~/repo',
      useLoginShell: true,
    );

    expect(
      command,
      startsWith(r'TERM="${TERM:-xterm-256color}" bash -lc '),
    );
    expect(command, contains(r'export TERM="${TERM:-xterm-256color}"'));
    expect(command, contains('. ~/.bashrc'));
    expect(command, contains('|| true'));
    expect(command, contains('--resume'));
    expect(command, contains('session-123'));
  });

  test('SSH pty uses prebuilt command without adding a second exec', () {
    final remoteCommand = const RemoteFlashskyaiCommandBuilder().buildCommand(
      remoteExecutablePath: '/opt/flash sky/flashskyai',
      arguments: ['--session-id', "abc'123"],
      workingDirectory: '/home/me/project dir',
      environment: {'FLASHSKYAI_TEAM': 'core team'},
    );

    final sessionCommand = SshPtyTransport.buildSessionCommand(remoteCommand);

    expect(sessionCommand, remoteCommand);
    expect(sessionCommand, isNot(contains('exec exec')));
    expect(sessionCommand, isNot(startsWith('exec cd ')));
  });
}
