@Tags(['integration', 'linux-pty'])
@Timeout(Duration(minutes: 5))
library;

/// The embedded SSH server's bare-shell path over a REAL OS pseudo-terminal
/// (flutter_pty_new) — the production default of [EmbeddedSshServer] with no
/// `ptySpawner` injected, and the coverage Task 9 deferred to integration:
///
///   EmbeddedSshServer (loopback, real temp app-data root; the device key is
///   issued directly because the QR/pairing TLS loop is already covered by
///   embedded_pairing_test.dart)
///     → dartssh2 SSHClient login with the device key
///     → `shell()` (pty-req + null command) spawns the login shell in a real
///       pseudo-terminal: the pty-req dimensions land in the terminal
///       (`stty size`), a window-change request resizes the real pty
///       end-to-end, a marker echoes back, and `exit` finishes the channel
///       with exit status 0.
///
/// `stty size` cannot succeed over pipes, so its output is the proof that a
/// real terminal (termios + window size) backs the channel — not a
/// pipe-substituted stand-in.
///
/// Needs `libflutter_pty_new.so` on the loader path (see DEVELOPMENT.md):
///
///   cd client
///   flutter build linux --debug
///   LD_LIBRARY_PATH=build/linux/x64/debug/bundle/lib \
///     flutter test --tags "integration && linux-pty" \
///       test/integration/embedded_shell_pty_integration_test.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart'
    show SSHClient, SSHKeyPair, SSHSocket;
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/connect/embedded_ssh_server.dart';
import 'package:teampilot/services/connect/paired_device_store.dart';
import 'package:teampilot/services/connect/ssh_device_key.dart';
import 'package:teampilot/services/io/local_filesystem.dart';

import 'support/integration_prerequisites.dart';

void main() {
  late Directory appDataRoot;
  late Directory homeDir;
  late EmbeddedSshServer server;
  late SSHClient sshClient;

  setUpAll(() async {
    appDataRoot = await Directory.systemTemp.createTemp(
      'teampilot-embedded-shell-pty-',
    );
    homeDir = await Directory.systemTemp.createTemp(
      'teampilot-embedded-shell-home-',
    );
    final fs = LocalFilesystem();
    final deviceStore = PairedDeviceStore(
      fs: fs,
      appDataRoot: appDataRoot.path,
    );
    final deviceKey = SshDeviceKey.generate();
    await deviceStore.issueDevice(
      deviceId: SshDeviceKey.deviceIdFor(deviceKey.openSshPublic),
      publicKey: deviceKey.openSshPublic,
      deviceName: 'integration-shell-pty',
    );
    server = EmbeddedSshServer(
      fs: fs,
      appDataRoot: appDataRoot.path,
      deviceStore: deviceStore,
      username: 'dev-user',
      homePath: homeDir.path,
      bindAddress: InternetAddress.loopbackIPv4,
      portOverride: 0,
      // No ptySpawner: production spawns the login shell in a real
      // flutter_pty pseudo-terminal.
    );
    await server.start();

    sshClient = SSHClient(
      await SSHSocket.connect('127.0.0.1', server.port),
      username: 'dev-user',
      identities: [SSHKeyPair.fromPem(deviceKey.pem).single],
      onVerifyHostKey: (type, fingerprint) =>
          utf8.decode(fingerprint) == server.hostKeyFingerprints.single,
    );
    await sshClient.authenticated;
  });

  tearDownAll(() async {
    try {
      await sshClient.close();
    } on Object {
      // The client was already torn down (or never created).
    }
    await server.stop();
    try {
      await appDataRoot.delete(recursive: true);
      await homeDir.delete(recursive: true);
    } on Object {
      // Best-effort cleanup of the temp roots.
    }
  });

  test('bare shell runs the login shell in a real pseudo-terminal', () async {
    IntegrationPrerequisites.skipUnlessNativePty();
    final session = await sshClient.shell();
    final output = StringBuffer();
    late final StreamSubscription<Uint8List> subscription;
    subscription = session.stdout.listen((data) {
      output.write(utf8.decode(data));
    });
    addTearDown(subscription.cancel);

    Future<void> waitFor(String needle, String stage) async {
      final deadline = DateTime.now().add(const Duration(seconds: 20));
      while (!output.toString().contains(needle)) {
        if (DateTime.now().isAfter(deadline)) {
          fail('$stage: shell never printed "$needle"\n$output');
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }

    // The pty-req dimensions (80x24 default) reached the real terminal —
    // `stty size` only works with a tty behind stdin/stdout.
    session.stdin.add(
      Uint8List.fromList(utf8.encode('stty size\r\n')),
    );
    await waitFor('24 80', 'initial dimensions');
    expect(output.toString(), isNot(contains('Inappropriate ioctl')));

    // A window-change request resizes the real pty end to end.
    session.resizeTerminal(120, 40);
    // Give the server a beat to apply the resize before probing it.
    await Future<void>.delayed(const Duration(milliseconds: 500));
    session.stdin.add(
      Uint8List.fromList(utf8.encode('stty size\r\n')),
    );
    await waitFor('40 120', 'resize');

    // The interactive round trip: a marker command echoes back.
    session.stdin.add(
      Uint8List.fromList(utf8.encode('echo INTEGRATION_PTY_SHELL_OK\r\n')),
    );
    await waitFor('INTEGRATION_PTY_SHELL_OK', 'marker echo');

    // A clean exit finishes the channel with the shell's exit status.
    session.stdin.add(Uint8List.fromList(utf8.encode('exit\r\n')));
    expect(await session.waitForExit(timeout: const Duration(seconds: 10)), 0);
    await session.done.timeout(const Duration(seconds: 10));
    await subscription.cancel();
  });
}
