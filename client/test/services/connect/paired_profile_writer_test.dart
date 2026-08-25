import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/models/ssh_reachability.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/ssh_known_host_repository.dart';
import 'package:teampilot/repositories/ssh_profile_repository.dart';
import 'package:teampilot/services/connect/paired_profile_writer.dart';
import 'package:teampilot/services/connect/pairing_http.dart';
import 'package:teampilot/services/connect/ssh_pairing_offer.dart';

import '../../support/in_memory_filesystem.dart';

SshPairingOffer offer({List<SshReachabilityEndpoint>? endpoints}) {
  return SshPairingOffer(
    v: 1,
    hostId: 'AbCdEf0123_-xyZ9',
    username: 'alice',
    displayName: 'Alice desktop',
    appDataRoot: '/home/alice/.local/share/com.hhoa.teampilot',
    endpoints:
        endpoints ??
        const [
          SshReachabilityEndpoint(
            kind: SshEndpointKind.lan,
            host: '192.168.1.20',
            port: 22,
          ),
          SshReachabilityEndpoint(
            kind: SshEndpointKind.extra,
            host: 'desktop.example.test',
            port: 2222,
          ),
        ],
    hostKeyFingerprints: const ['SHA256:host-key'],
    pairing: const SshPairingSession(
      token: 'abcdefghijklmnopqrstuvwxyz0123456789ABCDE',
      expiresAt: 1770000000000,
      url: 'https://192.168.1.20:2768/pair',
      tlsCertSha256: 'deadbeef',
    ),
  );
}

void main() {
  late SshProfileRepository profiles;
  late InMemorySshCredentialStore credentials;
  late InMemorySshKnownHostRepository knownHosts;
  late PairedProfileWriter writer;

  setUp(() {
    profiles = SshProfileRepository(
      rootDir: '/profiles',
      fs: InMemoryFilesystem(),
    );
    credentials = InMemorySshCredentialStore();
    knownHosts = InMemorySshKnownHostRepository();
    writer = PairedProfileWriter(
      profileRepository: profiles,
      credentialStore: credentials,
      knownHostRepository: knownHosts,
      idFactory: () => 'paired-profile',
      now: () => DateTime.utc(2026, 8, 25),
    );
  });

  test(
    'creates a private-key profile and persists its paired endpoints',
    () async {
      final profile = await writer.upsert(
        offer: offer(),
        result: const PairingPostResult(ok: true, profileHint: 'Alice desktop'),
        devicePem: 'PRIVATE KEY',
      );

      expect(profile.id, 'paired-profile');
      expect(profile.name, 'Alice desktop');
      expect(profile.host, '192.168.1.20');
      expect(profile.port, 22);
      expect(profile.username, 'alice');
      expect(profile.authType, SshAuthType.privateKey);
      expect(profile.lastAppDataRoot, offer().appDataRoot);
      expect(profile.pairedDesktopId, offer().hostId);
      expect(profile.endpoints, offer().endpoints);
      expect(profile.hostKeyFingerprints, offer().hostKeyFingerprints);
      expect(await credentials.loadPrivateKey(profile.id), 'PRIVATE KEY');
      expect(
        await knownHosts.findFingerprint(
          'alice@192.168.1.20:22',
          'ssh-ed25519',
        ),
        'SHA256:host-key',
      );
      expect(
        await knownHosts.findFingerprint(
          'alice@desktop.example.test:2222',
          'ssh-ed25519',
        ),
        'SHA256:host-key',
      );
    },
  );

  test(
    'updates the same paired desktop without touching manual profiles',
    () async {
      await profiles.save(
        const SshProfile(
          id: 'manual',
          name: 'Manual server',
          host: 'manual.example.test',
          username: 'manual',
        ),
      );
      final first = await writer.upsert(
        offer: offer(),
        result: const PairingPostResult(ok: true, profileHint: 'Alice desktop'),
        devicePem: 'KEY 1',
      );
      final second = await writer.upsert(
        offer: offer(
          endpoints: const [
            SshReachabilityEndpoint(
              kind: SshEndpointKind.lan,
              host: '192.168.1.21',
              port: 2200,
            ),
          ],
        ),
        result: const PairingPostResult(
          ok: true,
          profileHint: 'Renamed desktop',
        ),
        devicePem: 'KEY 2',
      );

      expect(second.id, first.id);
      expect(second.host, '192.168.1.21');
      expect(second.port, 2200);
      expect(second.name, 'Renamed desktop');
      expect(await credentials.loadPrivateKey(first.id), 'KEY 2');

      final saved = await profiles.loadAll();
      expect(saved, hasLength(2));
      expect(
        saved.where((profile) => profile.pairedDesktopId == offer().hostId),
        hasLength(1),
      );
      expect(
        saved.singleWhere((profile) => profile.id == 'manual').host,
        'manual.example.test',
      );
    },
  );
}
