import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/connect_cubit.dart';
import 'package:teampilot/models/ssh_reachability.dart';
import 'package:teampilot/services/connect/connect_backend_host.dart';
import 'package:teampilot/services/connect/connect_settings_store.dart';
import 'package:teampilot/services/connect/connect_ssh_backend.dart';
import 'package:teampilot/services/connect/paired_device_store.dart';
import 'package:teampilot/services/connect/ssh_pairing_offer.dart';

import '../support/fake_embedded_server.dart';
import '../support/in_memory_filesystem.dart';

PairedDeviceStore _deviceStore() =>
    PairedDeviceStore(fs: InMemoryFilesystem(), appDataRoot: '/app-data');

ConnectSettingsStore _settingsStore() => ConnectSettingsStore(
  fs: InMemoryFilesystem(),
  appDataRoot: '/app-data',
  generateHostId: () => 'abcdefghijklmnop',
);

ConnectBackendHost _hostFor(
  ConnectSshBackend embedded,
  ConnectSettingsStore settings, {
  ConnectSshBackend? system,
  bool systemSshdSelectable = false,
}) => ConnectBackendHost(
  embedded: embedded,
  system: system,
  settings: settings,
  systemSshdSelectable: systemSshdSelectable,
);

void main() {
  test('opens on first usable IPv4 and closes the pairing agent', () async {
    final starts = <String>[];
    var stops = 0;
    var regenerations = 0;
    final offer = _offer();
    final agent = ConnectAgentController(
      currentOffer: () => offer,
      startQrSession:
          ({
            required advertiseAddress,
            required username,
            required displayName,
            required appDataRoot,
          }) async {
            starts.add(advertiseAddress);
          },
      stopQrSession: () async => stops += 1,
      regenerateQr: () async => regenerations += 1,
      updateExtraEndpoints: (_) async {},
    );
    final deviceStore = _deviceStore();
    await deviceStore.issueDevice(
      deviceId: 'phone-1',
      publicKey: 'ssh-ed25519 AAAA',
      deviceName: 'Alice_phone',
    );
    final settingsStore = _settingsStore();
    final cubit = ConnectCubit(
      agent: agent,
      backends: _hostFor(FakeEmbeddedServer(), settingsStore),
      deviceStore: deviceStore,
      settingsStore: settingsStore,
      listNetworkAddresses: () async => const [
        ConnectNetworkAddress(
          name: 'Loopback',
          address: '127.0.0.1',
          isLoopback: true,
          isIpv4: true,
        ),
        ConnectNetworkAddress(
          name: 'IPv6',
          address: 'fe80::1',
          isLoopback: false,
          isIpv4: false,
        ),
        ConnectNetworkAddress(
          name: 'Wi-Fi',
          address: '192.168.1.20',
          isLoopback: false,
          isIpv4: true,
        ),
      ],
      username: 'alice',
      displayName: 'Alice desktop',
      appDataRoot: '/app-data',
    );
    addTearDown(cubit.close);

    await cubit.openQrSession();

    expect(cubit.state.selectedAddress, '192.168.1.20');
    expect(starts, ['192.168.1.20']);
    expect(cubit.state.offer, same(offer));
    expect(cubit.state.pairedDevices.single.deviceId, 'phone-1');
    expect(cubit.state.pairedDevices.single.name, 'Alice_phone');

    await cubit.regenerateQr();
    expect(regenerations, 1);

    await cubit.closeQrSession();
    expect(stops, 1);
  });

  test(
    'mirrors the embedded server state and stops pairing when it is down',
    () async {
      var starts = 0;
      var stops = 0;
      final offer = _offer();
      final agent = ConnectAgentController(
        currentOffer: () => offer,
        startQrSession:
            ({
              required advertiseAddress,
              required username,
              required displayName,
              required appDataRoot,
            }) async {
              starts += 1;
            },
        stopQrSession: () async => stops += 1,
        regenerateQr: () async {},
        updateExtraEndpoints: (_) async {},
      );
      final server = FakeEmbeddedServer(
        isListening: false,
        port: 0,
        hostKeyFingerprints: const ['SHA256:host-key'],
      );
      final settingsStore = _settingsStore();
      final cubit = ConnectCubit(
        agent: agent,
        backends: _hostFor(server, settingsStore),
        deviceStore: _deviceStore(),
        settingsStore: settingsStore,
        listNetworkAddresses: () async => const [
          ConnectNetworkAddress(
            name: 'Wi-Fi',
            address: '192.168.1.20',
            isLoopback: false,
            isIpv4: true,
          ),
        ],
        username: 'alice',
        displayName: 'Alice desktop',
        appDataRoot: '/app-data',
      );
      addTearDown(cubit.close);

      await cubit.openQrSession();

      expect(cubit.state.sshd.listening, isFalse);
      expect(cubit.state.sshd.port, 0);
      expect(cubit.state.sshd.fingerprints, isEmpty);
      expect(cubit.state.canPair, isFalse);
      expect(cubit.state.offer, isNull);
      expect(starts, 0);
      expect(stops, 1);

      // Once the server is listening the state mirrors its port and
      // fingerprints, and a refresh starts pairing again.
      server.isListening = true;
      server.port = 54321;
      await cubit.refresh();

      expect(cubit.state.sshd.listening, isTrue);
      expect(cubit.state.sshd.port, 54321);
      expect(cubit.state.sshd.fingerprints, ['SHA256:host-key']);
      expect(cubit.state.canPair, isTrue);
      expect(cubit.state.offer, same(offer));
      expect(starts, 1);
    },
  );

  test(
    'retry restarts the embedded server and refreshes the QR state',
    () async {
      var starts = 0;
      final offer = _offer();
      final agent = ConnectAgentController(
        currentOffer: () => offer,
        startQrSession:
            ({
              required advertiseAddress,
              required username,
              required displayName,
              required appDataRoot,
            }) async {
              starts += 1;
            },
        stopQrSession: () async {},
        regenerateQr: () async {},
        updateExtraEndpoints: (_) async {},
      );
      // A server whose first start failed: retry's restart makes it listen.
      final server = FakeEmbeddedServer(isListening: false, port: 0);
      server.onRestart = () async {
        server.isListening = true;
        server.port = 54321;
      };
      final settingsStore = _settingsStore();
      final cubit = ConnectCubit(
        agent: agent,
        backends: _hostFor(server, settingsStore),
        deviceStore: _deviceStore(),
        settingsStore: settingsStore,
        listNetworkAddresses: () async => const [
          ConnectNetworkAddress(
            name: 'Wi-Fi',
            address: '192.168.1.20',
            isLoopback: false,
            isIpv4: true,
          ),
        ],
        username: 'alice',
        displayName: 'Alice desktop',
        appDataRoot: '/app-data',
      );
      addTearDown(cubit.close);

      await cubit.openQrSession();
      expect(cubit.state.canPair, isFalse);

      await cubit.retryEmbeddedServer();

      expect(server.restarts, 1);
      expect(cubit.state.canPair, isTrue);
      expect(cubit.state.offer, same(offer));
      expect(starts, 1);
    },
  );

  test('retry keeps the down state when the restart fails', () async {
    final server = FakeEmbeddedServer(isListening: false, port: 0);
    server.restartError = StateError('port in use');
    final settingsStore = _settingsStore();
    final cubit = ConnectCubit(
      agent: ConnectAgentController(
        currentOffer: () => _offer(),
        startQrSession:
            ({
              required advertiseAddress,
              required username,
              required displayName,
              required appDataRoot,
            }) async {},
        stopQrSession: () async {},
        regenerateQr: () async {},
        updateExtraEndpoints: (_) async {},
      ),
      backends: _hostFor(server, settingsStore),
      deviceStore: _deviceStore(),
      settingsStore: settingsStore,
      listNetworkAddresses: () async => const [
        ConnectNetworkAddress(
          name: 'Wi-Fi',
          address: '192.168.1.20',
          isLoopback: false,
          isIpv4: true,
        ),
      ],
      username: 'alice',
      displayName: 'Alice desktop',
      appDataRoot: '/app-data',
    );
    addTearDown(cubit.close);

    await cubit.openQrSession();
    await cubit.retryEmbeddedServer();

    expect(server.restarts, 1);
    expect(cubit.state.canPair, isFalse);
    expect(cubit.state.loading, isFalse);
    expect(cubit.state.hasError, isFalse);
  });

  test('saving extra endpoints updates the active QR offer', () async {
    var offer = _offer();
    final agent = ConnectAgentController(
      currentOffer: () => offer,
      startQrSession:
          ({
            required advertiseAddress,
            required username,
            required displayName,
            required appDataRoot,
          }) async {},
      stopQrSession: () async {},
      regenerateQr: () async {},
      updateExtraEndpoints: (endpoints) async {
        offer = _offer(extraEndpoints: endpoints);
      },
    );
    final settingsStore = _settingsStore();
    final cubit = ConnectCubit(
      agent: agent,
      backends: _hostFor(FakeEmbeddedServer(), settingsStore),
      deviceStore: _deviceStore(),
      settingsStore: settingsStore,
      listNetworkAddresses: () async => const [
        ConnectNetworkAddress(
          name: 'Wi-Fi',
          address: '192.168.1.20',
          isLoopback: false,
          isIpv4: true,
        ),
      ],
      username: 'alice',
      displayName: 'Alice desktop',
      appDataRoot: '/app-data',
    );
    addTearDown(cubit.close);
    const endpoint = SshReachabilityEndpoint(
      kind: SshEndpointKind.extra,
      host: 'desktop.example.com',
      port: 2222,
    );

    await cubit.openQrSession();
    await cubit.saveSettings(extraEndpoints: const [endpoint], relayUrl: '');

    expect(cubit.state.offer!.endpoints, contains(endpoint));
  });

  test('revoke removes the device from the paired list', () async {
    final deviceStore = _deviceStore();
    await deviceStore.issueDevice(
      deviceId: 'phone-1',
      publicKey: 'ssh-ed25519 AAAA1',
      deviceName: 'Pixel',
    );
    await deviceStore.issueDevice(
      deviceId: 'phone-2',
      publicKey: 'ssh-ed25519 AAAA2',
      deviceName: 'Tablet',
    );
    final settingsStore = _settingsStore();
    final cubit = ConnectCubit(
      agent: ConnectAgentController(
        currentOffer: () => _offer(),
        startQrSession:
            ({
              required advertiseAddress,
              required username,
              required displayName,
              required appDataRoot,
            }) async {},
        stopQrSession: () async {},
        regenerateQr: () async {},
        updateExtraEndpoints: (_) async {},
      ),
      backends: _hostFor(FakeEmbeddedServer(), settingsStore),
      deviceStore: deviceStore,
      settingsStore: settingsStore,
      listNetworkAddresses: () async => const [
        ConnectNetworkAddress(
          name: 'Wi-Fi',
          address: '192.168.1.20',
          isLoopback: false,
          isIpv4: true,
        ),
      ],
      username: 'alice',
      displayName: 'Alice desktop',
      appDataRoot: '/app-data',
    );
    addTearDown(cubit.close);

    await cubit.openQrSession();
    expect(cubit.state.pairedDevices, hasLength(2));

    await cubit.revokeDevice('phone-1');

    expect(cubit.state.pairedDevices.map((device) => device.deviceId), [
      'phone-2',
    ]);
    expect(await deviceStore.hasDevice('phone-1'), isFalse);
  });

  test(
    'selectSshBackend updates sshBackend, sets rePairNotice, and restarts QR',
    () async {
      var starts = 0;
      ConnectSshBackend? replaced;
      final offer = _offer();
      final agent = ConnectAgentController(
        currentOffer: () => offer,
        startQrSession:
            ({
              required advertiseAddress,
              required username,
              required displayName,
              required appDataRoot,
            }) async {
              starts += 1;
            },
        stopQrSession: () async {},
        regenerateQr: () async {},
        updateExtraEndpoints: (_) async {},
        replaceSshBackend: (backend) async => replaced = backend,
      );
      final settingsStore = ConnectSettingsStore(
        fs: InMemoryFilesystem(),
        appDataRoot: '/app-data',
        generateHostId: () => 'abcdefghijklmnop',
      );
      final embedded = FakeEmbeddedServer();
      final system = FakeEmbeddedServer(
        isListening: false,
        port: 22,
        isEmbedded: false,
        hostKeyFingerprints: const ['SHA256:sys'],
      );
      system.onStart = () async {
        system.isListening = true;
      };
      final host = ConnectBackendHost(
        embedded: embedded,
        system: system,
        settings: settingsStore,
        systemSshdSelectable: true,
      );
      await host.startSelected();
      final cubit = ConnectCubit(
        agent: agent,
        backends: host,
        systemSshdHint: ConnectSystemSshdHint.linux,
        deviceStore: _deviceStore(),
        settingsStore: settingsStore,
        listNetworkAddresses: () async => const [
          ConnectNetworkAddress(
            name: 'Wi-Fi',
            address: '192.168.1.20',
            isLoopback: false,
            isIpv4: true,
          ),
        ],
        username: 'alice',
        displayName: 'Alice desktop',
        appDataRoot: '/app-data',
      );
      addTearDown(cubit.close);

      await cubit.openQrSession();
      expect(starts, 1);
      expect(cubit.state.sshBackend, ConnectSshBackendKind.embedded);
      expect(cubit.state.systemSshdSelectable, isTrue);
      expect(cubit.state.systemSshdHint, ConnectSystemSshdHint.linux);
      expect(cubit.state.rePairNotice, isFalse);

      await cubit.selectSshBackend(ConnectSshBackendKind.system);

      expect(replaced, same(system));
      expect(cubit.state.sshBackend, ConnectSshBackendKind.system);
      expect(cubit.state.rePairNotice, isTrue);
      expect(starts, 2);

      cubit.ackRePairNotice();
      expect(cubit.state.rePairNotice, isFalse);
    },
  );

  test(
    'revokeDevice revokes the backend key before dropping the device',
    () async {
      final deviceStore = _deviceStore();
      await deviceStore.issueDevice(
        deviceId: 'phone-1',
        publicKey: 'ssh-ed25519 AAAA1',
        deviceName: 'Pixel',
      );
      final server = FakeEmbeddedServer();
      var keyStillPresentDuringRevoke = false;
      server.onRevokePublicKey = (key) async {
        keyStillPresentDuringRevoke =
            await deviceStore.publicKeyForDevice('phone-1') == key;
      };
      final settingsStore = ConnectSettingsStore(
        fs: InMemoryFilesystem(),
        appDataRoot: '/app-data',
        generateHostId: () => 'abcdefghijklmnop',
      );
      final cubit = ConnectCubit(
        agent: ConnectAgentController(
          currentOffer: () => _offer(),
          startQrSession:
              ({
                required advertiseAddress,
                required username,
                required displayName,
                required appDataRoot,
              }) async {},
          stopQrSession: () async {},
          regenerateQr: () async {},
          updateExtraEndpoints: (_) async {},
        ),
        backends: ConnectBackendHost(
          embedded: server,
          system: null,
          settings: settingsStore,
          systemSshdSelectable: false,
        ),
        deviceStore: deviceStore,
        settingsStore: settingsStore,
        listNetworkAddresses: () async => const [
          ConnectNetworkAddress(
            name: 'Wi-Fi',
            address: '192.168.1.20',
            isLoopback: false,
            isIpv4: true,
          ),
        ],
        username: 'alice',
        displayName: 'Alice desktop',
        appDataRoot: '/app-data',
      );
      addTearDown(cubit.close);

      await cubit.openQrSession();
      expect(cubit.state.pairedDevices.single.deviceId, 'phone-1');

      await cubit.revokeDevice('phone-1');

      expect(server.revokedPublicKeys, ['ssh-ed25519 AAAA1']);
      expect(keyStillPresentDuringRevoke, isTrue);
      expect(cubit.state.pairedDevices, isEmpty);
      expect(await deviceStore.publicKeyForDevice('phone-1'), isNull);
    },
  );

  test(
    'revokeDevice revokes the system key after switching to embedded',
    () async {
      const publicKey = 'ssh-ed25519 AAAA1';
      final deviceStore = _deviceStore();
      await deviceStore.issueDevice(
        deviceId: 'phone-1',
        publicKey: publicKey,
        deviceName: 'Pixel',
      );
      final settingsStore = _settingsStore();
      final embedded = FakeEmbeddedServer();
      final system = FakeEmbeddedServer(
        isListening: false,
        port: 22,
        isEmbedded: false,
        hostKeyFingerprints: const ['SHA256:sys'],
      );
      system.onStart = () async {
        system.isListening = true;
      };
      final host = ConnectBackendHost(
        embedded: embedded,
        system: system,
        settings: settingsStore,
        systemSshdSelectable: true,
      );
      await host.startSelected();
      await host.select(ConnectSshBackendKind.system);
      await system.authorizePublicKey(publicKey);
      ConnectSshBackend? replaced;
      final cubit = ConnectCubit(
        agent: ConnectAgentController(
          currentOffer: () => _offer(),
          startQrSession:
              ({
                required advertiseAddress,
                required username,
                required displayName,
                required appDataRoot,
              }) async {},
          stopQrSession: () async {},
          regenerateQr: () async {},
          updateExtraEndpoints: (_) async {},
          replaceSshBackend: (backend) async => replaced = backend,
        ),
        backends: host,
        deviceStore: deviceStore,
        settingsStore: settingsStore,
        listNetworkAddresses: () async => const [
          ConnectNetworkAddress(
            name: 'Wi-Fi',
            address: '192.168.1.20',
            isLoopback: false,
            isIpv4: true,
          ),
        ],
        username: 'alice',
        displayName: 'Alice desktop',
        appDataRoot: '/app-data',
      );
      addTearDown(cubit.close);

      await cubit.openQrSession();
      await cubit.selectSshBackend(ConnectSshBackendKind.embedded);
      expect(replaced, same(embedded));
      expect(cubit.state.sshBackend, ConnectSshBackendKind.embedded);

      await cubit.revokeDevice('phone-1');

      expect(system.revokedPublicKeys, [publicKey]);
      expect(embedded.revokedPublicKeys, [publicKey]);
      expect(await deviceStore.hasDevice('phone-1'), isFalse);
    },
  );

  test(
    'selectSshBackend emits hasError and keeps host/agent on embedded when start fails',
    () async {
      ConnectSshBackend? replaced;
      final settingsStore = _settingsStore();
      final embedded = FakeEmbeddedServer();
      final system = FakeEmbeddedServer(
        isListening: false,
        port: 22,
        isEmbedded: false,
        hostKeyFingerprints: const ['SHA256:sys'],
      );
      system.onStart = () async {
        throw StateError('system sshd down');
      };
      final host = ConnectBackendHost(
        embedded: embedded,
        system: system,
        settings: settingsStore,
        systemSshdSelectable: true,
      );
      await host.startSelected();
      final cubit = ConnectCubit(
        agent: ConnectAgentController(
          currentOffer: () => _offer(),
          startQrSession:
              ({
                required advertiseAddress,
                required username,
                required displayName,
                required appDataRoot,
              }) async {},
          stopQrSession: () async {},
          regenerateQr: () async {},
          updateExtraEndpoints: (_) async {},
          replaceSshBackend: (backend) async => replaced = backend,
        ),
        backends: host,
        deviceStore: _deviceStore(),
        settingsStore: settingsStore,
        listNetworkAddresses: () async => const [
          ConnectNetworkAddress(
            name: 'Wi-Fi',
            address: '192.168.1.20',
            isLoopback: false,
            isIpv4: true,
          ),
        ],
        username: 'alice',
        displayName: 'Alice desktop',
        appDataRoot: '/app-data',
      );
      addTearDown(cubit.close);

      await cubit.openQrSession();
      await cubit.selectSshBackend(ConnectSshBackendKind.system);

      expect(cubit.state.hasError, isTrue);
      expect(cubit.state.sshBackend, ConnectSshBackendKind.embedded);
      expect(cubit.state.rePairNotice, isFalse);
      expect(host.kind, ConnectSshBackendKind.embedded);
      expect(host.current, same(embedded));
      expect(replaced, same(embedded));
    },
  );
}

SshPairingOffer _offer({
  List<SshReachabilityEndpoint> extraEndpoints = const [],
}) => SshPairingOffer(
  v: 1,
  hostId: 'abcdefghijklmnop',
  username: 'alice',
  displayName: 'Alice desktop',
  appDataRoot: '/app-data',
  endpoints: [
    const SshReachabilityEndpoint(
      kind: SshEndpointKind.lan,
      host: '192.168.1.20',
      port: 22,
    ),
    ...extraEndpoints,
  ],
  hostKeyFingerprints: const ['SHA256:host-key'],
  pairing: const SshPairingSession(
    token: 'invite-token',
    expiresAt: 1_800_000_000_000,
    url: 'https://192.168.1.20:2768/pair',
    tlsCertSha256:
        '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
  ),
);
