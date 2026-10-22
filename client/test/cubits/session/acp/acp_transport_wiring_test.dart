import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/session/acp/acp_transport_wiring.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/services/acp/acp_process_transport.dart';
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

  test('buildAcpRemoteCommand encodes the non-login legacy string exactly', () {
    final command = buildAcpRemoteCommand(
      profile: _profile,
      argv: const ['opencode', 'acp'],
      workingDirectory: '/work/proj',
      env: const {
        'HOME': '/home/u',
        'ANTHROPIC_API_KEY': '',
      },
    );
    expect(
      command,
      r"cd '/work/proj' && export 'HOME'='/home/u' && "
      r'export PATH="$HOME/.local/share/com.hhoa.teampilot/toolchain/node/current/bin:$HOME/.local/bin:$PATH" && '
      r"exec 'opencode' 'acp'",
    );
    // Empty-valued env dropped; no login shell (`bash -lc` banner would
    // corrupt the NDJSON stdout channel).
    expect(command, isNot(contains('ANTHROPIC_API_KEY')));
    expect(command, isNot(contains('bash -lc')));
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
    // Remote ACP has no local OS process to measure.
    expect(started.pid, isNull);
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

  test(
    'localAcpTransportStarter forwards the spawned process pid',
    () async {
      final starter = localAcpTransportStarter();
      final started = await starter(
        argv: const ['cat'],
        env: Platform.environment,
        workingDirectory: Directory.systemTemp.path,
        onStderr: null,
      );

      expect(started.pid, isNotNull);
      expect(started.pid, (started.transport as AcpProcessTransport).pid);

      await started.transport.close();
    },
    skip: Platform.isWindows ? 'spawns POSIX cat' : false,
    timeout: const Timeout(Duration(seconds: 15)),
  );

  test('acpStarterForTarget throws when a remote target has no SSH launch', () {
    expect(
      () => acpStarterForTarget(
        launchTarget: RuntimeTarget.ssh('p1', label: 'host'),
        sshLaunch: null,
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('acpStarterForTarget builds a non-login remote command for a remote '
      'target', () async {
    String? seenCommand;
    final starter = acpStarterForTarget(
      launchTarget: RuntimeTarget.ssh('p1', label: 'host'),
      sshLaunch: (
        profile: _profile,
        openChannel: (command) async {
          seenCommand = command;
          return _FakeChannel();
        },
      ),
    );
    expect(starter, isNotNull);

    await starter!(
      argv: const ['opencode', 'acp'],
      env: const {
        'HOME': '/home/u',
        'ANTHROPIC_API_KEY': '',
      },
      workingDirectory: '/work/proj',
      onStderr: null,
    );

    expect(seenCommand, isNotNull);
    // Executable plus a `cd` to the working directory.
    expect(seenCommand, contains('opencode'));
    expect(seenCommand, contains("cd '/work/proj'"));
    // Empty-valued env entry dropped; the non-empty one is exported.
    expect(seenCommand, isNot(contains('ANTHROPIC_API_KEY')));
    expect(seenCommand, contains("export 'HOME'='/home/u'"));
    // Non-login-shell encoding (no `bash -lc` wrapper).
    expect(seenCommand, isNot(contains('bash -lc')));
  });
}
