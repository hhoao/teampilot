import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ssh_reachability.dart';
import 'package:teampilot/services/connect/authorized_keys_file.dart';
import 'package:teampilot/services/connect/connect_agent.dart';
import 'package:teampilot/services/connect/connect_relay_client.dart';
import 'package:teampilot/services/connect/connect_settings_store.dart';
import 'package:teampilot/services/connect/paired_device_store.dart';
import 'package:teampilot/services/connect/pairing_certificate.dart';
import 'package:teampilot/services/connect/pairing_http.dart';
import 'package:teampilot/services/connect/pairing_token_gate.dart';
import 'package:teampilot/services/connect/sshd_presence.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  final now = DateTime.utc(2026, 8, 25, 12);
  const hostId = 'AbCdEf0123_-xyZ9';
  const publicKey = 'ssh-ed25519 AAAA';

  late _FakePairingBind binding;
  late PairingTokenGate gate;
  late String authorizedKeys;

  AuthorizedKeysFile keys() => AuthorizedKeysFile(
    path: '/home/alice/.ssh/authorized_keys',
    read: (_) async => authorizedKeys,
    write: (_, value) async => authorizedKeys = value,
    chmod: (_, {required mode}) async {},
  );

  ConnectAgent agent({
    SshdPresenceSnapshot presence = _listeningPresence,
    SshdPresenceProbe? probe,
    List<SshReachabilityEndpoint> extraEndpoints = const [],
    PairedDeviceStore? deviceStore,
    ConnectRelayRegistration? relayRegistration,
    GrantGenerator? generateGrant,
  }) => ConnectAgent(
    probe: probe ?? () async => presence,
    keys: keys(),
    gate: gate,
    bind: binding.call,
    certificateProvider: _CannedCertificateProvider(const [1, 2, 3, 4]),
    now: () => now,
    stableHostId: (_) async => hostId,
    extraEndpoints: extraEndpoints,
    deviceStore: deviceStore,
    relayRegistration: relayRegistration,
    generateGrant: generateGrant,
  );

  setUp(() {
    binding = _FakePairingBind();
    gate = PairingTokenGate();
    authorizedKeys = '';
  });

  test('does not mint or bind when sshd is not listening', () async {
    final connectAgent = agent(
      presence: const SshdPresenceSnapshot(
        listening: false,
        port: 22,
        fingerprints: [],
        enableHint: 'enable sshd',
      ),
    );

    await connectAgent.startQrSession(
      advertiseAddress: '192.168.1.20',
      username: 'alice',
      displayName: 'Alice desktop',
      appDataRoot: '/app-data',
    );

    expect(connectAgent.currentOffer, isNull);
    expect(binding.calls, isEmpty);
  });

  test(
    'does not mint or bind when the SSH handshake finds no host key',
    () async {
      final connectAgent = agent(
        presence: const SshdPresenceSnapshot(
          listening: true,
          port: 22,
          fingerprints: [],
          enableHint: '',
        ),
      );

      await connectAgent.startQrSession(
        advertiseAddress: '192.168.1.20',
        username: 'alice',
        displayName: 'Alice desktop',
        appDataRoot: '/app-data',
      );

      expect(connectAgent.currentOffer, isNull);
      expect(binding.calls, isEmpty);
    },
  );

  test('mints a LAN offer bound only to the advertised address', () async {
    final connectAgent = agent(
      presence: const SshdPresenceSnapshot(
        listening: true,
        port: 2222,
        fingerprints: ['SHA256:host-key'],
        enableHint: '',
      ),
      extraEndpoints: const [
        SshReachabilityEndpoint(
          kind: SshEndpointKind.extra,
          host: 'vpn.example.test',
          port: 2200,
        ),
      ],
    );

    await connectAgent.startQrSession(
      advertiseAddress: '192.168.1.20',
      username: 'alice',
      displayName: 'Alice desktop',
      appDataRoot: '/app-data',
    );

    final offer = connectAgent.currentOffer!;
    expect(binding.calls.single.address.address, '192.168.1.20');
    expect(offer.hostId, hostId);
    expect(offer.hostKeyFingerprints, ['SHA256:host-key']);
    expect(offer.endpoints, const [
      SshReachabilityEndpoint(
        kind: SshEndpointKind.lan,
        host: '192.168.1.20',
        port: 2222,
      ),
      SshReachabilityEndpoint(
        kind: SshEndpointKind.extra,
        host: 'vpn.example.test',
        port: 2200,
      ),
    ]);
    expect(offer.pairing.url, 'https://192.168.1.20:2768/pair');
    expect(
      offer.pairing.expiresAt,
      now.add(const Duration(minutes: 10)).millisecondsSinceEpoch,
    );
    expect(
      offer.pairing.tlsCertSha256,
      sha256.convert(const [1, 2, 3, 4]).toString(),
    );
    expect(offer.relay, isNull);
  });

  test(
    'stop closes the listener, clears the offer, and invalidates token',
    () async {
      final connectAgent = agent(presence: _listeningPresence);
      await _start(connectAgent);
      final oldToken = connectAgent.currentOffer!.pairing.token;

      await connectAgent.stopQrSession();

      expect(binding.closed, isTrue);
      expect(connectAgent.currentOffer, isNull);
      expect(gate.consume(oldToken, now), isFalse);
    },
  );

  test('stop waits for and closes an in-flight start binding', () async {
    final probeStarted = Completer<void>();
    final releaseProbe = Completer<void>();
    final connectAgent = agent(
      probe: () async {
        probeStarted.complete();
        await releaseProbe.future;
        return _listeningPresence;
      },
    );

    final starting = _start(connectAgent);
    await probeStarted.future;
    final stopping = connectAgent.stopQrSession();
    releaseProbe.complete();
    await Future.wait([starting, stopping]);

    expect(binding.closed, isTrue);
    expect(connectAgent.currentOffer, isNull);
    expect(gate.hasActiveToken, isFalse);
  });

  test('regenerate replaces and invalidates the previous token', () async {
    final connectAgent = agent(presence: _listeningPresence);
    await _start(connectAgent);
    final oldToken = connectAgent.currentOffer!.pairing.token;

    await connectAgent.regenerateQr();

    final newToken = connectAgent.currentOffer!.pairing.token;
    expect(newToken, isNot(oldToken));
    expect(gate.consume(oldToken, now), isFalse);
    expect(gate.consume(newToken, now), isTrue);
  });

  test('updating extra endpoints remints the active offer', () async {
    final connectAgent = agent(presence: _listeningPresence);
    await _start(connectAgent);
    final oldToken = connectAgent.currentOffer!.pairing.token;
    const endpoint = SshReachabilityEndpoint(
      kind: SshEndpointKind.extra,
      host: 'desktop.example.com',
      port: 2222,
    );

    await connectAgent.updateExtraEndpoints(const [endpoint]);

    expect(connectAgent.currentOffer!.endpoints, contains(endpoint));
    expect(connectAgent.currentOffer!.pairing.token, isNot(oldToken));
    expect(binding.calls, hasLength(1));
    expect(gate.consume(oldToken, now), isFalse);
  });

  test('valid incoming POST writes the device authorized key', () async {
    final connectAgent = agent(presence: _listeningPresence);
    await _start(connectAgent);
    final response = Completer<({int statusCode, Map<String, Object?> body})>();

    binding.requests.add(
      PairingHttpRequest(
        method: 'POST',
        uri: Uri(path: '/pair'),
        body: PairingPostBody(
          token: connectAgent.currentOffer!.pairing.token,
          deviceId: 'pixel-1',
          deviceName: 'Pixel',
          publicKey: publicKey,
        ),
        respond: ({required statusCode, required body}) async {
          response.complete((statusCode: statusCode, body: body));
        },
      ),
    );

    final result = await response.future;
    expect(result.statusCode, HttpStatus.ok);
    expect(result.body['ok'], isTrue);
    expect(authorizedKeys, contains('device=pixel-1'));
  });

  test('rejects an oversized content length before listening', () async {
    var listened = false;
    final source = StreamController<List<int>>(onListen: () => listened = true);
    addTearDown(() {
      source.close();
    });

    await expectLater(
      readPairingPostBody(
        source.stream,
        contentLength: maxPairingRequestBytes + 1,
      ),
      throwsA(isA<PairingRequestTooLargeException>()),
    );

    expect(listened, isFalse);
  });

  test('stops consuming chunked request bytes at the size limit', () async {
    var emittedChunks = 0;
    Stream<List<int>> oversizedBody() async* {
      emittedChunks += 1;
      yield List<int>.filled(40000, 97);
      emittedChunks += 1;
      yield List<int>.filled(40000, 97);
      emittedChunks += 1;
      yield const [97];
    }

    await expectLater(
      readPairingPostBody(oversizedBody()),
      throwsA(isA<PairingRequestTooLargeException>()),
    );

    expect(emittedChunks, 2);
  });

  group('relay', () {
    const registration = ConnectRelayRegistration(
      url: 'ws://relay.example.test',
      endpointHost: 'relay.example.test',
      endpointPort: 443,
    );

    Future<({int statusCode, Map<String, Object?> body})> postPair(
      ConnectAgent connectAgent, {
      String deviceId = 'pixel-1',
    }) {
      final response =
          Completer<({int statusCode, Map<String, Object?> body})>();
      binding.requests.add(
        PairingHttpRequest(
          method: 'POST',
          uri: Uri(path: '/pair'),
          body: PairingPostBody(
            token: connectAgent.currentOffer!.pairing.token,
            deviceId: deviceId,
            deviceName: 'Pixel',
            publicKey: publicKey,
          ),
          respond: ({required statusCode, required body}) async {
            response.complete((statusCode: statusCode, body: body));
          },
        ),
      );
      return response.future;
    }

    test('issues a hashed device grant when a relay is registered',
        () async {
      final store = PairedDeviceStore(
        fs: InMemoryFilesystem(),
        appDataRoot: '/data',
        generateGrant: () => 'grant-token-abc',
      );
      final connectAgent = agent(
        deviceStore: store,
        relayRegistration: registration,
        generateGrant: () => 'grant-token-abc',
      );
      await _start(connectAgent);

      final result = await postPair(connectAgent);

      expect(result.statusCode, HttpStatus.ok);
      expect(result.body['relayGrant'], 'grant-token-abc');
      expect(
        await store.validateGrant(
          hostId: hostId,
          deviceId: 'pixel-1',
          grant: 'grant-token-abc',
        ),
        isTrue,
      );
      expect(await store.hasDevice('pixel-1'), isTrue);
    });

    test('LAN pairing succeeds without any relay and mints no grant',
        () async {
      final store = PairedDeviceStore(
        fs: InMemoryFilesystem(),
        appDataRoot: '/data',
        generateGrant: () => 'grant-token-abc',
      );
      final connectAgent = agent(deviceStore: store);
      await _start(connectAgent);

      final result = await postPair(connectAgent);

      expect(result.statusCode, HttpStatus.ok);
      expect(result.body.containsKey('relayGrant'), isFalse);
      expect(await store.hasDevice('pixel-1'), isFalse);
    });

    test(
      'pair dials accept only the live invite while the QR session runs',
      () async {
        final connectAgent = agent(relayRegistration: registration);
        await _start(connectAgent);
        final invite = connectAgent.currentOffer!.pairing.token;

        expect(
          await connectAgent.validateRelayDial(
            ConnectRelayDialRequest(
              channel: 'pair',
              deviceId: 'pixel-1',
              inviteToken: invite,
            ),
          ),
          isTrue,
        );

        // Wrong or stale invites never pass.
        expect(
          await connectAgent.validateRelayDial(
            const ConnectRelayDialRequest(channel: 'pair', inviteToken: 'nope'),
          ),
          isFalse,
        );
        expect(
          await connectAgent.validateRelayDial(
            const ConnectRelayDialRequest(channel: 'pair'),
          ),
          isFalse,
        );

        // After the QR closes the pairing channel is dead everywhere.
        await connectAgent.stopQrSession();
        expect(
          await connectAgent.validateRelayDial(
            ConnectRelayDialRequest(
              channel: 'pair',
              deviceId: 'pixel-1',
              inviteToken: invite,
            ),
          ),
          isFalse,
        );
        expect(
          await connectAgent.resolveRelayTarget('pair'),
          isNull,
        );
      },
    );

    test('ssh dials require a grant bound to device and install', () async {
      final store = PairedDeviceStore(
        fs: InMemoryFilesystem(),
        appDataRoot: '/data',
        generateGrant: () => 'grant-token-abc',
      );
      await store.issueGrant(hostId: hostId, deviceId: 'pixel-1');
      final connectAgent = agent(deviceStore: store);
      await _start(connectAgent);

      Future<bool> dial({
        String? deviceId = 'pixel-1',
        String? grant = 'grant-token-abc',
      }) {
        return connectAgent.validateRelayDial(
          ConnectRelayDialRequest(
            channel: 'ssh',
            deviceId: deviceId,
            relayGrant: grant,
          ),
        );
      }

      expect(await dial(), isTrue);

      // Wrong device, wrong install, revoked, missing credential.
      expect(await dial(deviceId: 'other-phone'), isFalse);
      expect(
        await dial(grant: 'wrong-token'),
        isFalse,
      );
      expect(
        await connectAgent.validateRelayDial(
          const ConnectRelayDialRequest(channel: 'ssh', deviceId: 'pixel-1'),
        ),
        isFalse,
      );

      // The grant survives a QR stop but dies with revocation.
      await connectAgent.stopQrSession();
      expect(await dial(), isTrue);
      await store.revokeDevice('pixel-1');
      expect(await dial(), isFalse);
    });
  });

  test('ConnectSettingsStore persists one stable host ID', () async {
    final fs = InMemoryFilesystem();
    var generated = 0;
    final store = ConnectSettingsStore(
      fs: fs,
      appDataRoot: '/app-data',
      generateHostId: () {
        generated += 1;
        return hostId;
      },
    );

    final first = await store.loadOrCreateHostId();
    final second = await store.loadOrCreateHostId();
    final reloaded = await ConnectSettingsStore(
      fs: fs,
      appDataRoot: '/app-data',
    ).loadOrCreateHostId();

    expect(first, hostId);
    expect(second, hostId);
    expect(reloaded, hostId);
    expect(generated, 1);
    expect(
      await fs.readString('/app-data/connect/settings.json'),
      contains(hostId),
    );
  });

  test('ConnectSettingsStore persists endpoint and relay settings', () async {
    final fs = InMemoryFilesystem();
    final store = ConnectSettingsStore(
      fs: fs,
      appDataRoot: '/app-data',
      generateHostId: () => hostId,
    );
    const endpoints = [
      SshReachabilityEndpoint(
        kind: SshEndpointKind.extra,
        host: 'desktop.example.com',
        port: 2222,
      ),
    ];

    await store.save(
      extraEndpoints: endpoints,
      relayUrl: 'wss://relay.example.com',
    );
    final reloaded = await ConnectSettingsStore(
      fs: fs,
      appDataRoot: '/app-data',
    ).load();

    expect(reloaded.hostId, hostId);
    expect(reloaded.extraEndpoints, endpoints);
    expect(reloaded.relayUrl, 'wss://relay.example.com');
  });

  test(
    'ConnectTls creates a fresh pinned leaf without a process runner',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'teampilot-connect-tls-',
      );
      addTearDown(() => root.delete(recursive: true));

      final certificate = await ConnectTls(
        now: () => now,
      ).generate(appDataRoot: root.path);

      expect(certificate.tlsContext, isA<SecurityContext>());
      expect(certificate.leafDer, isNotEmpty);
      expect(
        certificate.sha256Hex,
        sha256.convert(certificate.leafDer).toString(),
      );
      expect(await File(certificate.certificatePath).exists(), isTrue);
      expect(await File(certificate.privateKeyPath).exists(), isTrue);
      if (!Platform.isWindows) {
        expect(
          (await File(certificate.privateKeyPath).stat()).mode & 0x1ff,
          0x180,
        );
        expect(
          (await File(certificate.certificatePath).stat()).mode & 0x1ff,
          0x180,
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 1)),
  );
}

const _listeningPresence = SshdPresenceSnapshot(
  listening: true,
  port: 22,
  fingerprints: ['SHA256:host-key'],
  enableHint: '',
);

Future<void> _start(ConnectAgent agent) => agent.startQrSession(
  advertiseAddress: '192.168.1.20',
  username: 'alice',
  displayName: 'Alice desktop',
  appDataRoot: '/app-data',
);

class _CannedCertificateProvider implements PairingCertificateProvider {
  const _CannedCertificateProvider(this.der);

  final List<int> der;

  @override
  Future<PairingCertificate> generate({required String appDataRoot}) async {
    return PairingCertificate(
      tlsContext: Object(),
      leafDer: der,
      certificatePath: '$appDataRoot/connect/pairing-cert.pem',
      privateKeyPath: '$appDataRoot/connect/pairing-key.pem',
    );
  }
}

class _FakePairingBind {
  final requests = StreamController<PairingHttpRequest>();
  final calls = <({InternetAddress address, Object tlsContext})>[];
  var closed = false;

  Future<PairingBinding> call(
    InternetAddress address,
    Object tlsContext,
  ) async {
    calls.add((address: address, tlsContext: tlsContext));
    return PairingBinding(
      address: address,
      port: 2768,
      close: () async => closed = true,
      requests: requests.stream,
    );
  }
}
