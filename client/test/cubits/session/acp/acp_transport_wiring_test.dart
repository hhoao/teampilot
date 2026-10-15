import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/session/acp/acp_transport_wiring.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/services/acp/acp_ssh_transport.dart';

class _FakeChannel implements AcpSshChannel {
  final exit = Completer<int>();
  @override
  Stream<Uint8List> get stdout => const Stream.empty();
  @override
  Stream<Uint8List> get stderr => const Stream.empty();
  @override
  Future<int> get exitCode => exit.future;
  @override
  void write(Uint8List data) {}
  @override
  Future<void> closeStdin() async {}
  @override
  void kill() {}
  @override
  void dispose() {}
}

const _profile = SshProfile(
  id: 'p1',
  name: 'host',
  host: 'host',
  username: 'u',
  authType: SshAuthType.password,
);

void main() {
  test('buildAcpRemoteCommand drops empty env values', () {
    final command = buildAcpRemoteCommand(
      profile: _profile,
      argv: const ['opencode', 'acp'],
      workingDirectory: '/work/proj',
      env: const {
        'HOME': '/home/u',
        'ANTHROPIC_API_KEY': '',
      },
    );
    expect(command, contains('opencode'));
    expect(command, contains('/work/proj'));
    expect(command, isNot(contains('ANTHROPIC_API_KEY')));
    expect(command, contains('HOME'));
  });

  test('sshAcpTransportStarter opens a channel for the built command', () async {
    String? seenCommand;
    final channel = _FakeChannel();
    final starter = sshAcpTransportStarter(
      profile: _profile,
      openChannel: (command) async {
        seenCommand = command;
        return channel;
      },
    );

    final started = await starter(
      argv: const ['opencode', 'acp'],
      env: const {},
      workingDirectory: '/work/proj',
      onStderr: null,
    );

    expect(seenCommand, isNotNull);
    expect(seenCommand, contains('opencode'));
    expect(started.transport, isA<AcpSshTransport>());
    // The exit future is wired to the channel, not completed yet.
    // (`AcpStartedTransport.processExitCode` is nullable, hence the `!`.)
    expect(started.processExitCode, isNotNull);
    expect(
      await started.processExitCode!.timeout(
        const Duration(milliseconds: 100),
        onTimeout: () => -1,
      ),
      -1,
    );
    channel.exit.complete(0);
    expect(await started.processExitCode, 0);
  });

  test('acpStarterForTarget is null for a local target', () {
    expect(
      acpStarterForTarget(
        launchTarget: RuntimeTarget.local(),
        sshLaunch: null,
      ),
      isNull,
    );
  });

  test('acpStarterForTarget throws when a remote target has no SSH launch', () {
    expect(
      () => acpStarterForTarget(
        launchTarget: RuntimeTarget.ssh('p1', label: 'host'),
        sshLaunch: null,
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('acpStarterForTarget returns an SSH starter for a remote target', () {
    final starter = acpStarterForTarget(
      launchTarget: RuntimeTarget.ssh('p1', label: 'host'),
      sshLaunch: (profile: _profile, openChannel: (_) async => _FakeChannel()),
    );
    expect(starter, isNotNull);
  });
}
