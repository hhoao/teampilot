@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart'
    show
        SSHAuthError,
        SSHChannelOpenError,
        SSHClient,
        SSHKeyPair,
        SSHSocket;
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/connect/embedded_ssh_server.dart';
import 'package:teampilot/services/connect/paired_device_store.dart';
import 'package:teampilot/services/connect/ssh_device_key.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:tp_sshd/tp_sshd.dart' show SSHHostInfo, TpExecCodec;

import '../../support/in_memory_filesystem.dart';

/// Throwaway ed25519 device key generated for these tests only
/// (ssh-keygen -t ed25519 -N '' -C 'tp-task7-throwaway-device'). The pub
/// line below is the OpenSSH one-line format pairing registers.
const testDevicePem = '''
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
QyNTUxOQAAACBWs5pOr024BBwHc+E5Wws/SJFdWuxOzjt/1fPzf5Dh2gAAAKD02zF59Nsx
eQAAAAtzc2gtZWQyNTUxOQAAACBWs5pOr024BBwHc+E5Wws/SJFdWuxOzjt/1fPzf5Dh2g
AAAEAhA9Fe5rHduMSMgKOILhnc60e5nS5hznEiJk3yUbvqQlazmk6vTbgEHAdz4TlbCz9I
kV1a7E7OO3/V8/N/kOHaAAAAGXRwLXRhc2s3LXRocm93YXdheS1kZXZpY2UBAgME
-----END OPENSSH PRIVATE KEY-----
''';

const testDevicePubLine =
    'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFazmk6vTbgEHAdz4TlbCz9IkV1a7E7OO3/V8/N/kOHa '
    'tp-task7-throwaway-device';

/// A second throwaway key, never registered — the unregistered-client case.
const otherDevicePem = '''
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
QyNTUxOQAAACDb2kdNPmIDINvKtYJL1pe8VVw9B/wudmJGhUyiVQ30PwAAAKBCbddPQm3X
TwAAAAtzc2gtZWQyNTUxOQAAACDb2kdNPmIDINvKtYJL1pe8VVw9B/wudmJGhUyiVQ30Pw
AAAECTWQG5LiG2G8cXzdnXs0M8RT6fR8VAymsLRhbbTKVsOdvaR00+YgMg28q1gkvWl7xV
XD0H/C52YkaFTKJVDfQ/AAAAGHRwLXRhc2s3LXRocm93YXdheS1vdGhlcgECAwQF
-----END OPENSSH PRIVATE KEY-----
''';

/// Reproduces the revocation race: dartssh2 (no probe for a local key pair)
/// sends one signed publickey request, so a login performs exactly two
/// registry lookups for the device key — the signed-auth check and the
/// record-time lookup `_recordDeviceConnection` makes after the userauth
/// success was already sent. This store revokes the device in the middle of
/// that second lookup, i.e. after the connection authenticated but before
/// the server finished recording which device owns it.
/// A store whose registry-changed stream getter throws: a failure in the
/// post-bind half of `start()` (after the listener is already listening).
class _BrokenRegistryStore extends PairedDeviceStore {
  _BrokenRegistryStore({required super.fs, required super.appDataRoot});

  @override
  Stream<void> get deviceRegistryChanged => throw StateError('registry broken');
}

class _RevokeRacingStore extends PairedDeviceStore {
  _RevokeRacingStore({required super.fs, required super.appDataRoot});

  static const _recordLookup = 2;
  int _lookups = 0;
  final raced = Completer<void>();

  @override
  Future<String?> deviceIdForPublicKey(String publicKeyLine) async {
    if (++_lookups == _recordLookup) {
      await revokeDevice('phone-1');
      if (!raced.isCompleted) raced.complete();
      return null;
    }
    return super.deviceIdForPublicKey(publicKeyLine);
  }
}

void main() {
  late InMemoryFilesystem fs;
  late PairedDeviceStore store;

  setUp(() {
    fs = InMemoryFilesystem();
    store = PairedDeviceStore(fs: fs, appDataRoot: '/data');
  });

  EmbeddedSshServer newServer({int? portOverride = 0}) => EmbeddedSshServer(
        fs: fs,
        appDataRoot: '/data',
        deviceStore: store,
        username: 'user',
        homePath: '/home/user',
        bindAddress: InternetAddress.loopbackIPv4,
        portOverride: portOverride,
      );

  /// Connects a real dartssh2 client to [server], optionally pinning the
  /// host key to the fingerprint the server reports.
  Future<SSHClient> connectTo(
    EmbeddedSshServer server, {
    String pem = testDevicePem,
    bool Function(String type, List<int> fingerprint)? onVerifyHostKey,
  }) async {
    return SSHClient(
      await SSHSocket.connect('127.0.0.1', server.port),
      username: 'user',
      identities: [SSHKeyPair.fromPem(pem).single],
      onVerifyHostKey: onVerifyHostKey,
    );
  }

  test('starts, answers a real dartssh2 login with an issued device key, and stops', () async {
    await store.issueDevice(deviceId: 'phone-1', publicKey: testDevicePubLine);
    final server = newServer();
    await server.start();
    addTearDown(server.stop);

    expect(server.isListening, isTrue);
    // portOverride 0 asked for an ephemeral port; the getter must report
    // the actually bound one.
    expect(server.port, greaterThan(0));
    expect(server.hostKeyFingerprints, hasLength(1));
    expect(server.hostKeyFingerprints.single, startsWith('SHA256:'));

    final client = await connectTo(
      server,
      // The host key the client saw must be the one the store persisted.
      onVerifyHostKey: (type, fingerprint) =>
          utf8.decode(fingerprint) == server.hostKeyFingerprints.single,
    );
    addTearDown(client.close);
    await client.authenticated;
  });

  test('unregistered key is rejected', () async {
    final server = newServer();
    await server.start();
    addTearDown(server.stop);

    final client = await connectTo(server, pem: otherDevicePem);
    await expectLater(client.authenticated, throwsA(isA<SSHAuthError>()));
    await client.close();
  });

  test('revoked device loses its live connection', () async {
    await store.issueDevice(deviceId: 'phone-1', publicKey: testDevicePubLine);
    final server = newServer();
    await server.start();
    addTearDown(server.stop);

    final client = await connectTo(server);
    await client.authenticated;
    await server.revokeDevice('phone-1');
    await expectLater(
      client.done.timeout(const Duration(seconds: 5)),
      completes,
    );
    await client.close();
  });

  test('revoke racing the auth-success record still tears down the connection', () async {
    final racingStore = _RevokeRacingStore(fs: fs, appDataRoot: '/data');
    await racingStore.issueDevice(
      deviceId: 'phone-1',
      publicKey: testDevicePubLine,
    );
    final server = EmbeddedSshServer(
      fs: fs,
      appDataRoot: '/data',
      deviceStore: racingStore,
      username: 'user',
      homePath: '/home/user',
      bindAddress: InternetAddress.loopbackIPv4,
      portOverride: 0,
    );
    await server.start();
    addTearDown(server.stop);

    final client = await connectTo(server);
    await client.authenticated;
    // The store revoked the device while the server was still recording the
    // just-authenticated connection — the race window the fail-closed
    // guarantee must cover.
    await racingStore.raced.future.timeout(const Duration(seconds: 5));
    await expectLater(
      client.done.timeout(const Duration(seconds: 5)),
      completes,
    );
    await client.close();
  });

  test('exec round trip answers the host-info query', () async {
    await store.issueDevice(deviceId: 'phone-1', publicKey: testDevicePubLine);
    final server = newServer();
    await server.start();
    addTearDown(server.stop);

    final client = await connectTo(server);
    addTearDown(client.close);
    await client.authenticated;

    final session = await client.execute(TpExecCodec.encodeHostInfoQuery());
    final stdout = await utf8.decoder.bind(session.stdout).join();
    final info = SSHHostInfo.fromJson(stdout);
    expect(info.platform, Platform.operatingSystem);
    expect(info.osUser, Platform.environment['USER'] ?? 'unknown');
  });

  test('host-info reports the probed elevation, failing closed on probe error',
      () async {
    await store.issueDevice(deviceId: 'phone-1', publicKey: testDevicePubLine);

    /// Full login against a server built with [probe], returning the
    /// `elevated` fact its host-info answer carries.
    Future<bool> elevatedFor(Future<bool> Function() probe) async {
      final server = EmbeddedSshServer(
        fs: fs,
        appDataRoot: '/data',
        deviceStore: store,
        username: 'user',
        homePath: '/home/user',
        bindAddress: InternetAddress.loopbackIPv4,
        portOverride: 0,
        elevationProbe: probe,
      );
      await server.start();
      addTearDown(server.stop);

      final client = await connectTo(server);
      addTearDown(client.close);
      await client.authenticated;

      final session = await client.execute(TpExecCodec.encodeHostInfoQuery());
      final stdout = await utf8.decoder.bind(session.stdout).join();
      return SSHHostInfo.fromJson(stdout).elevated;
    }

    expect(await elevatedFor(() async => true), isTrue);
    expect(await elevatedFor(() async => false), isFalse);
    // Fail closed: an elevation that cannot be determined is reported as
    // elevated so the dangerous-launch gate stays strict.
    expect(
      await elevatedFor(() async => throw StateError('probe unavailable')),
      isTrue,
    );
  });

  test('a failure after the bind rolls the listener back', () async {
    const port = 49557;
    final server = EmbeddedSshServer(
      fs: fs,
      appDataRoot: '/data',
      deviceStore: _BrokenRegistryStore(fs: fs, appDataRoot: '/data'),
      username: 'user',
      homePath: '/home/user',
      bindAddress: InternetAddress.loopbackIPv4,
      portOverride: port,
    );

    await expectLater(server.start(), throwsStateError);
    // Not half-listening: the state was reset alongside the listener.
    expect(server.isListening, isFalse);
    expect(server.port, 0);
    // The listener socket was really closed — the port is bindable again.
    final rebound = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      port,
    );
    addTearDown(rebound.close);
  });

  test('restart stops and rebinds on a fresh listener', () async {
    await store.issueDevice(deviceId: 'phone-1', publicKey: testDevicePubLine);
    final server = newServer();
    await server.start();
    addTearDown(server.stop);

    final firstClient = await connectTo(server);
    await firstClient.authenticated;
    await firstClient.close();

    await server.restart();
    expect(server.isListening, isTrue);
    // portOverride 0 is per-bind ephemeral, so the restart binds a fresh
    // port; with a fixed port it would rebind the same one.
    expect(server.port, greaterThan(0));

    // The server answers a full login again after the restart.
    final secondClient = await connectTo(server);
    addTearDown(secondClient.close);
    await secondClient.authenticated;
  });

  test('bind conflict on the persisted port re-picks and binds', () async {
    const conflictedPort = 49555;
    await fs.ensureDir(fs.pathContext.dirname(
      fs.pathContext.join('/data', 'connect', 'settings.json'),
    ));
    await fs.writeString(
      fs.pathContext.join('/data', 'connect', 'settings.json'),
      jsonEncode({'v': 1, 'embeddedPort': conflictedPort}),
    );
    // Occupy the persisted port so the first bind attempt fails.
    final squatter = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      conflictedPort,
    );
    addTearDown(squatter.close);

    final server = newServer(portOverride: null);
    await server.start();
    addTearDown(server.stop);

    expect(server.isListening, isTrue);
    expect(server.port, isNot(conflictedPort));
  });

  test('explicit port conflict throws EmbeddedSshServerStartException', () async {
    const conflictedPort = 49556;
    final squatter = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      conflictedPort,
    );
    addTearDown(squatter.close);

    final server = EmbeddedSshServer(
      fs: fs,
      appDataRoot: '/data',
      deviceStore: store,
      username: 'user',
      homePath: '/home/user',
      bindAddress: InternetAddress.loopbackIPv4,
      portOverride: conflictedPort,
    );
    await expectLater(
      server.start(),
      throwsA(isA<EmbeddedSshServerStartException>()),
    );
    expect(server.isListening, isFalse);
  });

  group('transport trace gating', () {
    test('off by default and for unrecognized env values', () {
      expect(EmbeddedSshServer.transportTraceEnabledByEnv(null), isFalse);
      expect(EmbeddedSshServer.transportTraceEnabledByEnv(''), isFalse);
      expect(EmbeddedSshServer.transportTraceEnabledByEnv('0'), isFalse);
      expect(EmbeddedSshServer.transportTraceEnabledByEnv('false'), isFalse);
      expect(EmbeddedSshServer.transportTraceEnabledByEnv(' OFF '), isFalse);
    });

    test('on for TP_SSH_TRACE truthy values', () {
      expect(EmbeddedSshServer.transportTraceEnabledByEnv('1'), isTrue);
      expect(EmbeddedSshServer.transportTraceEnabledByEnv('true'), isTrue);
      expect(EmbeddedSshServer.transportTraceEnabledByEnv(' ON '), isTrue);
      expect(EmbeddedSshServer.transportTraceEnabledByEnv('True'), isTrue);
    });
  });

  group('forwarding injection (real loopback sockets, real temp root)', () {
    late Directory appDataRoot;
    late PairedDeviceStore deviceStore;
    late EmbeddedSshServer server;

    setUp(() async {
      appDataRoot = await Directory.systemTemp.createTemp(
        'teampilot-embedded-forward-',
      );
      final lfs = LocalFilesystem();
      deviceStore = PairedDeviceStore(
        fs: lfs,
        appDataRoot: appDataRoot.path,
      );
      server = EmbeddedSshServer(
        fs: lfs,
        appDataRoot: appDataRoot.path,
        deviceStore: deviceStore,
        username: 'user',
        homePath: '${appDataRoot.path}/home',
        bindAddress: InternetAddress.loopbackIPv4,
        portOverride: 0,
      );
    });

    tearDown(() async {
      await server.stop();
      try {
        await appDataRoot.delete(recursive: true);
      } on Object {
        // Best-effort cleanup of the temp root.
      }
    });

    /// Issues a fresh device key, starts the server, and logs a real
    /// dartssh2 client in with it.
    Future<SSHClient> logIn() async {
      final deviceKey = SshDeviceKey.generate();
      await deviceStore.issueDevice(
        deviceId: SshDeviceKey.deviceIdFor(deviceKey.openSshPublic),
        publicKey: deviceKey.openSshPublic,
      );
      await server.start();
      addTearDown(server.stop);

      final client = SSHClient(
        await SSHSocket.connect('127.0.0.1', server.port),
        username: 'user',
        identities: [SSHKeyPair.fromPem(deviceKey.pem).single],
        onVerifyHostKey: (type, fingerprint) =>
            utf8.decode(fingerprint) == server.hostKeyFingerprints.single,
      );
      addTearDown(client.close);
      await client.authenticated;
      return client;
    }

    test('forwardRemote binds loopback (remote forwarding not regressed)',
        () async {
      final client = await logIn();

      final forward = await client.forwardRemote(host: '127.0.0.1', port: 0);
      expect(forward, isNotNull);
      expect(forward!.host, '127.0.0.1');
      expect(forward.port, greaterThan(0));
      // cancel, not close(): the fork's SSHRemoteForward.close() waits for
      // the connections controller's done event, which is only delivered
      // once something listens to the stream.
      expect(await client.cancelForwardRemote(forward), isTrue);
    });

    test('forwardLocal to a loopback target round-trips bytes', () async {
      // A real echo service on the desktop under test: bytes dialed by the
      // server must come back over the direct-tcpip channel.
      final listener = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(listener.close);
      listener.listen((socket) {
        socket.listen((data) => socket.add(data), onDone: socket.close);
      });

      final client = await logIn();
      final channel = await client.forwardLocal('127.0.0.1', listener.port);

      final echoed = Completer<void>();
      final received = StringBuffer();
      channel.stream.listen((data) {
        received.write(utf8.decode(data));
        if (!echoed.isCompleted &&
            received.toString().contains('forward-ping')) {
          echoed.complete();
        }
      });
      channel.sink.add(utf8.encode('forward-ping'));
      await echoed.future.timeout(const Duration(seconds: 15));
      expect(received.toString(), 'forward-ping');
      await channel.close();
    });

    test('forwardLocal to a non-loopback target is refused with reason 1',
        () async {
      final client = await logIn();

      await expectLater(
        client.forwardLocal('store.example', 80),
        throwsA(isA<SSHChannelOpenError>().having((e) => e.code, 'code', 1)),
      );
    });
  });
}
