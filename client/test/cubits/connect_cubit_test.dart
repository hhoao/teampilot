import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/connect_cubit.dart';
import 'package:teampilot/models/ssh_reachability.dart';
import 'package:teampilot/services/connect/connect_settings_store.dart';
import 'package:teampilot/services/connect/embedded_ssh_server.dart';
import 'package:teampilot/services/connect/paired_device_store.dart';
import 'package:teampilot/services/connect/ssh_pairing_offer.dart';

import '../support/in_memory_filesystem.dart';

class _FakeEmbeddedServer implements EmbeddedSshServerHandle {
  _FakeEmbeddedServer({
    required this.isListening,
    required this.port,
    required this.hostKeyFingerprints,
  });

  @override
  bool isListening;

  @override
  int port;

  @override
  final List<String> hostKeyFingerprints;
}

PairedDeviceStore _deviceStore() =>
    PairedDeviceStore(fs: InMemoryFilesystem(), appDataRoot: '/app-data');

const _listeningServer = _ServerFixture(
  isListening: true,
  port: 54321,
  fingerprints: ['SHA256:host-key'],
);

class _ServerFixture {
  const _ServerFixture({
    required this.isListening,
    required this.port,
    required this.fingerprints,
  });

  final bool isListening;
  final int port;
  final List<String> fingerprints;

  _FakeEmbeddedServer toHandle() => _FakeEmbeddedServer(
    isListening: isListening,
    port: port,
    hostKeyFingerprints: fingerprints,
  );
}

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
    final cubit = ConnectCubit(
      agent: agent,
      embeddedServer: _listeningServer.toHandle(),
      deviceStore: deviceStore,
      settingsStore: ConnectSettingsStore(
        fs: InMemoryFilesystem(),
        appDataRoot: '/app-data',
        generateHostId: () => 'abcdefghijklmnop',
      ),
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

  test('mirrors the embedded server state and stops pairing when it is down',
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
    final server = _FakeEmbeddedServer(
      isListening: false,
      port: 0,
      hostKeyFingerprints: const ['SHA256:host-key'],
    );
    final cubit = ConnectCubit(
      agent: agent,
      embeddedServer: server,
      deviceStore: _deviceStore(),
      settingsStore: ConnectSettingsStore(
        fs: InMemoryFilesystem(),
        appDataRoot: '/app-data',
        generateHostId: () => 'abcdefghijklmnop',
      ),
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
    final cubit = ConnectCubit(
      agent: agent,
      embeddedServer: _listeningServer.toHandle(),
      deviceStore: _deviceStore(),
      settingsStore: ConnectSettingsStore(
        fs: InMemoryFilesystem(),
        appDataRoot: '/app-data',
        generateHostId: () => 'abcdefghijklmnop',
      ),
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
      embeddedServer: _listeningServer.toHandle(),
      deviceStore: deviceStore,
      settingsStore: ConnectSettingsStore(
        fs: InMemoryFilesystem(),
        appDataRoot: '/app-data',
        generateHostId: () => 'abcdefghijklmnop',
      ),
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

    expect(
      cubit.state.pairedDevices.map((device) => device.deviceId),
      ['phone-2'],
    );
    expect(await deviceStore.hasDevice('phone-1'), isFalse);
  });
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
