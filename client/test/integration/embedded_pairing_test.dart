@Tags(['integration', 'cross-platform'])
@Timeout(Duration(minutes: 5))
library;

/// The spec's full embedded-connect pairing loop, end to end over real
/// dart:io sockets and a real temp app-data root — no fakes past the pairing
/// TLS binding:
///
///   EmbeddedSshServer (loopback, ephemeral port, real PairedDeviceStore)
///     → ConnectAgent QR session (production self-signed TLS pairing
///       listener + offer v2)
///     → phone-side pairing POST with a freshly generated device key, TLS
///       cert pinned by the SHA-256 from the offer
///     → dartssh2 SSHClient login with the just-paired device key
///     → tp1: exec round trip and the host-info query
///     → SFTP mkdir/write/read/listdir/rmdir through EmbeddedSftpFilesystem
///     → bare-shell channel: null command dispatched to the server-side
///       OS-native shell
///     → revokeDevice tears the live connection down
///
/// The shell runs over plain pipes through the [PtySpawner] seam:
/// flutter_pty needs the Flutter engine, so its real path is covered by the
/// Windows manual test matrix instead (see the PR description).
///
/// Run:
///   dart run tool/run_tests.dart --tags integration \
///     test/integration/embedded_pairing_test.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dartssh2/dartssh2.dart'
    show SSHClient, SSHKeyPair, SSHSignal, SSHSocket;
import 'package:dartssh2/protocol.dart' show SftpFileOpenMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ssh_reachability.dart';
import 'package:teampilot/services/connect/connect_agent.dart';
import 'package:teampilot/services/connect/connect_settings_store.dart';
import 'package:teampilot/services/connect/embedded_process_factories.dart';
import 'package:teampilot/services/connect/embedded_ssh_server.dart';
import 'package:teampilot/services/connect/paired_device_store.dart';
import 'package:teampilot/services/connect/pairing_certificate.dart';
import 'package:teampilot/services/connect/pairing_token_gate.dart';
import 'package:teampilot/services/connect/ssh_device_key.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:tp_sshd/tp_sshd.dart'
    show SSHExecRequest, SSHHostInfo, TpExecCodec;

void main() {
  late Directory appDataRoot;
  late Directory homeDir;
  late PairedDeviceStore deviceStore;
  late EmbeddedSshServer server;
  late ConnectAgent agent;

  // The phone-side fixtures, filled in by the pairing test and consumed by
  // every stage after it — the stages form one chained loop.
  late ({String pem, String openSshPublic}) deviceKey;
  late String deviceId;
  late SSHClient sshClient;

  setUpAll(() async {
    appDataRoot = await Directory.systemTemp.createTemp(
      'teampilot-embedded-pairing-',
    );
    homeDir = await Directory.systemTemp.createTemp(
      'teampilot-embedded-home-',
    );
    final fs = LocalFilesystem();
    deviceStore = PairedDeviceStore(fs: fs, appDataRoot: appDataRoot.path);
    server = EmbeddedSshServer(
      fs: fs,
      appDataRoot: appDataRoot.path,
      deviceStore: deviceStore,
      username: 'dev-user',
      homePath: homeDir.path,
      bindAddress: InternetAddress.loopbackIPv4,
      portOverride: 0,
      ptySpawner: _pipePtySpawner,
    );
    await server.start();
    agent = ConnectAgent(
      embeddedServer: server,
      deviceStore: deviceStore,
      gate: PairingTokenGate(),
      bind: bindPairingHttps,
      certificateProvider: ConnectTls(),
      now: DateTime.now,
      stableHostId: (root) =>
          ConnectSettingsStore(fs: fs, appDataRoot: root).loadOrCreateHostId(),
    );
    await agent.startQrSession(
      advertiseAddress: '127.0.0.1',
      username: 'dev-user',
      displayName: 'Integration desktop',
      appDataRoot: appDataRoot.path,
    );
  });

  tearDownAll(() async {
    // No-op when a stage before the login never produced a client.
    try {
      await sshClient.close();
    } on Object {
      // The client was already torn down (or never created).
    }
    await agent.stopQrSession();
    await server.stop();
    try {
      await appDataRoot.delete(recursive: true);
      await homeDir.delete(recursive: true);
    } on Object {
      // Best-effort cleanup of the temp roots.
    }
  });

  test('QR session mints a v2 offer pointing at the embedded server', () {
    final offer = agent.currentOffer!;
    expect(offer.v, 2);
    expect(offer.emb, isTrue);
    expect(offer.username, 'dev-user');
    expect(offer.endpoints.first.kind, SshEndpointKind.lan);
    expect(offer.endpoints.first.host, '127.0.0.1');
    expect(offer.endpoints.first.port, server.port);
    expect(offer.hostKeyFingerprints, server.hostKeyFingerprints);
    expect(offer.pairing.url, startsWith('https://127.0.0.1:'));
    expect(offer.pairing.token, isNotEmpty);
  });

  test('pairing POST over pinned TLS registers the fresh device key', () async {
    deviceKey = SshDeviceKey.generate();
    deviceId = SshDeviceKey.deviceIdFor(deviceKey.openSshPublic);
    final offer = agent.currentOffer!;

    final httpClient = HttpClient()
      ..badCertificateCallback = (certificate, host, port) =>
          sha256.convert(certificate.der).toString() ==
          offer.pairing.tlsCertSha256;
    addTearDown(() {
      httpClient.badCertificateCallback = null;
      httpClient.close();
    });

    final request = await httpClient.postUrl(Uri.parse(offer.pairing.url));
    request.headers.contentType = ContentType.json;
    request.write(
      jsonEncode({
        'token': offer.pairing.token,
        'deviceId': deviceId,
        'deviceName': 'integration-phone',
        'publicKey': deviceKey.openSshPublic,
      }),
    );
    final response = await request.close();
    final body =
        jsonDecode(await utf8.decoder.bind(response).join())
            as Map<String, Object?>;

    expect(response.statusCode, HttpStatus.ok);
    expect(body['ok'], isTrue);
    // The registry entry lives on the real disk under the temp app-data root
    // (no relay is registered, so no grant is expected — devices only).
    expect(
      (await deviceStore.listDevices()).map((device) => device.deviceId),
      contains(deviceId),
    );
    expect(await deviceStore.isValidDeviceKey(deviceKey.openSshPublic), isTrue);
  });

  test('dartssh2 client logs in with the paired device key', () async {
    sshClient = SSHClient(
      await SSHSocket.connect('127.0.0.1', server.port),
      username: 'dev-user',
      identities: [SSHKeyPair.fromPem(deviceKey.pem).single],
      onVerifyHostKey: (type, fingerprint) =>
          utf8.decode(fingerprint) ==
          agent.currentOffer!.hostKeyFingerprints.single,
    );
    await sshClient.authenticated;
  });

  test('tp1 exec round trip echoes argv without a shell', () async {
    final session = await sshClient.execute(
      TpExecCodec.encode(
        const SSHExecRequest(argv: ['echo', 'integration', 'exec']),
      ),
    );
    final stdout = await utf8.decoder.bind(session.stdout).join();
    expect(stdout.trim(), 'integration exec');
    expect(await session.waitForExit(), 0);
  });

  test('tp1 host-info query is answered without spawning a process', () async {
    final session = await sshClient.execute(TpExecCodec.encodeHostInfoQuery());
    final stdout = await utf8.decoder.bind(session.stdout).join();
    final info = SSHHostInfo.fromJson(stdout);
    expect(info.platform, Platform.operatingSystem);
    expect(info.shell, isNotEmpty);
    expect(await session.waitForExit(), 0);
  });

  test('SFTP round trip mkdir/write/read/listdir/rmdir hits the real disk',
      () async {
    final sftp = await sshClient.sftp();
    addTearDown(sftp.close);

    final dirPath = '${homeDir.path}/tp-embedded-sftp';
    final filePath = '$dirPath/round-trip.txt';
    const content = 'embedded sftp round trip';

    await sftp.mkdir(dirPath);
    final writer = await sftp.open(
      filePath,
      mode: SftpFileOpenMode.create | SftpFileOpenMode.write,
    );
    await writer.writeBytes(Uint8List.fromList(utf8.encode(content)));
    await writer.close();

    final reader = await sftp.open(filePath, mode: SftpFileOpenMode.read);
    final readBack = await reader.readBytes();
    await reader.close();
    expect(utf8.decode(readBack), content);

    expect(
      (await sftp.listdir(dirPath)).map((entry) => entry.filename),
      contains('round-trip.txt'),
    );
    // The listing served the real temp home, not an in-memory fake.
    expect(File(filePath).readAsStringSync(), content);

    await sftp.remove(filePath);
    await sftp.rmdir(dirPath);
    expect(FileSystemEntity.typeSync(dirPath), FileSystemEntityType.notFound);
  });

  test('bare-shell channel runs the OS-native shell through the pty seam',
      () async {
    final session = await sshClient.shell();
    final output = StringBuffer();
    final sawNeedle = Completer<void>();
    late final StreamSubscription<Uint8List> subscription;
    subscription = session.stdout.listen((data) {
      output.write(utf8.decode(data));
      if (output.toString().contains('INTEGRATION_SHELL_OK') &&
          !sawNeedle.isCompleted) {
        sawNeedle.complete();
      }
    });
    addTearDown(subscription.cancel);

    // \r\n line endings work for both POSIX shells and PowerShell.
    session.stdin.add(
      Uint8List.fromList(utf8.encode('echo INTEGRATION_SHELL_OK\r\n')),
    );
    await sawNeedle.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () => fail('shell never echoed the marker\n$output'),
    );
    await subscription.cancel();
    expect(output.toString(), contains('INTEGRATION_SHELL_OK'));

    // The signal path: RFC 4254 SIGTERM reaches the spawned shell and the
    // channel finishes.
    session.kill(SSHSignal.TERM);
    await session.done.timeout(const Duration(seconds: 10));
  });

  test('revoking the device tears down the live connection', () async {
    expect(await server.revokeDevice(deviceId), isTrue);
    await sshClient.done.timeout(const Duration(seconds: 10));
  });
}

/// A dart:io [Process] with pipes standing in for an OS pseudo-terminal:
/// enough to prove the null-command shell dispatch and the signal path end
/// to end without the Flutter engine flutter_pty needs. The spawner spawns
/// exactly the executable the production factory would (see
/// [EmbeddedShellSelection]).
Future<PtyLike> _pipePtySpawner({
  required String executable,
  required List<String> arguments,
  required Map<String, String> environment,
  required int columns,
  required int rows,
  String? workingDirectory,
}) async {
  return _PipePty(
    await Process.start(
      executable,
      arguments,
      environment: environment,
      workingDirectory: workingDirectory,
    ),
  );
}

class _PipePty implements PtyLike {
  _PipePty(this._process);

  final Process _process;

  @override
  Stream<Uint8List> get output => _process.stdout.cast<Uint8List>();

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  void write(Uint8List data) => _process.stdin.add(data);

  @override
  void resize(int columns, int rows) {
    // Pipes have no window to resize.
  }

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) =>
      _process.kill(signal);
}
