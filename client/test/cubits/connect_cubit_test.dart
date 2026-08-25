import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/connect_cubit.dart';
import 'package:teampilot/models/ssh_reachability.dart';
import 'package:teampilot/services/connect/authorized_keys_file.dart';
import 'package:teampilot/services/connect/connect_settings_store.dart';
import 'package:teampilot/services/connect/ssh_pairing_offer.dart';
import 'package:teampilot/services/connect/sshd_presence.dart';

import '../support/in_memory_filesystem.dart';

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
    );
    var authorizedKeys =
        'ssh-ed25519 AAAA teampilot-pair device=phone-1 name=Alice_phone\n';
    final keys = AuthorizedKeysFile(
      path: '/home/alice/.ssh/authorized_keys',
      read: (_) async => authorizedKeys,
      write: (_, value) async => authorizedKeys = value,
      chmod: (_, {required mode}) async {},
    );
    final cubit = ConnectCubit(
      agent: agent,
      probeSshd: () async => const SshdPresenceSnapshot(
        listening: true,
        port: 22,
        fingerprints: ['SHA256:host-key'],
        enableHint: '',
      ),
      authorizedKeys: keys,
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

    await cubit.regenerateQr();
    expect(regenerations, 1);

    await cubit.closeQrSession();
    expect(stops, 1);
  });
}

SshPairingOffer _offer() => SshPairingOffer(
  v: 1,
  hostId: 'abcdefghijklmnop',
  username: 'alice',
  displayName: 'Alice desktop',
  appDataRoot: '/app-data',
  endpoints: const [
    SshReachabilityEndpoint(
      kind: SshEndpointKind.lan,
      host: '192.168.1.20',
      port: 22,
    ),
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
