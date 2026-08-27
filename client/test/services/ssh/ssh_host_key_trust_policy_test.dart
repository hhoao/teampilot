import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/repositories/ssh_known_host_repository.dart';
import 'package:teampilot/services/ssh/ssh_client_factory.dart';

void main() {
  const profile = SshProfile(
    id: 'p1',
    name: 'dev',
    host: 'example.com',
    port: 22,
    username: 'alice',
  );

  test(
    'TOFU accepts and persists first host key without a UI prompt',
    () async {
      final repository = InMemorySshKnownHostRepository();
      final policy = SshHostKeyTrustPolicy(knownHostRepository: repository);

      final accepted = await policy.verify(
        profile: profile,
        keyType: 'ssh-ed25519',
        fingerprint: Uint8List.fromList([1, 2, 3]),
      );

      expect(accepted, isTrue);
      expect(
        await repository.findFingerprint(profile.hostIdentifier, 'ssh-ed25519'),
        '01:02:03',
      );
    },
  );

  test('known host key matches are accepted', () async {
    final repository = InMemorySshKnownHostRepository();
    await repository.saveFingerprint(
      profile.hostIdentifier,
      'ssh-ed25519',
      '01:02:03',
    );
    final policy = SshHostKeyTrustPolicy(knownHostRepository: repository);

    final accepted = await policy.verify(
      profile: profile,
      keyType: 'ssh-ed25519',
      fingerprint: Uint8List.fromList([1, 2, 3]),
    );

    expect(accepted, isTrue);
  });

  test(
    'mismatched host key is rejected unless the prompt accepts it',
    () async {
      final repository = InMemorySshKnownHostRepository();
      await repository.saveFingerprint(
        profile.hostIdentifier,
        'ssh-ed25519',
        '01:02:03',
      );
      final policy = SshHostKeyTrustPolicy(knownHostRepository: repository);

      final accepted = await policy.verify(
        profile: profile,
        keyType: 'ssh-ed25519',
        fingerprint: Uint8List.fromList([9, 9, 9]),
      );

      expect(accepted, isFalse);
      expect(
        await repository.findFingerprint(profile.hostIdentifier, 'ssh-ed25519'),
        '01:02:03',
      );
    },
  );

  test(
    'OpenSSH SHA256 fingerprints are stored as the identity string',
    () async {
      final repository = InMemorySshKnownHostRepository();
      final policy = SshHostKeyTrustPolicy(knownHostRepository: repository);
      const identity = 'SHA256:nThbg6kXUpJWGl7E1IGOCspRomTxdCARLviKw6E5SY8';
      final fingerprint = Uint8List.fromList(identity.codeUnits);

      final accepted = await policy.verify(
        profile: profile,
        keyType: 'ssh-ed25519',
        fingerprint: fingerprint,
      );

      expect(accepted, isTrue);
      expect(
        await repository.findFingerprint(profile.hostIdentifier, 'ssh-ed25519'),
        identity,
      );
    },
  );

  test(
    'paired profiles accept only their QR-pinned host key without prompting',
    () async {
      const paired = SshProfile(
        id: 'paired',
        name: 'desktop',
        host: '192.168.1.20',
        username: 'alice',
        hostKeyFingerprints: ['SHA256:expected'],
      );
      final repository = InMemorySshKnownHostRepository();
      var promptCount = 0;
      final policy = SshHostKeyTrustPolicy(
        knownHostRepository: repository,
        onHostKeyPrompt: (_) async {
          promptCount++;
          return true;
        },
      );

      expect(
        await policy.verify(
          profile: paired,
          keyType: 'ssh-ed25519',
          fingerprint: Uint8List.fromList('SHA256:expected'.codeUnits),
        ),
        isTrue,
      );
      expect(
        await policy.verify(
          profile: paired,
          keyType: 'ssh-ed25519',
          fingerprint: Uint8List.fromList('SHA256:other'.codeUnits),
        ),
        isFalse,
      );
      expect(promptCount, 0);
      expect(await repository.loadAll(), isEmpty);
    },
  );

  test('prompt can accept a mismatched host key and replace the pin', () async {
    final repository = InMemorySshKnownHostRepository();
    await repository.saveFingerprint(
      profile.hostIdentifier,
      'ssh-ed25519',
      '01:02:03',
    );
    HostKeyPromptInfo? prompted;
    final policy = SshHostKeyTrustPolicy(
      knownHostRepository: repository,
      onHostKeyPrompt: (info) async {
        prompted = info;
        return true;
      },
    );
    const identity = 'SHA256:nThbg6kXUpJWGl7E1IGOCspRomTxdCARLviKw6E5SY8';

    final accepted = await policy.verify(
      profile: profile,
      keyType: 'ssh-ed25519',
      fingerprint: Uint8List.fromList(identity.codeUnits),
    );

    expect(accepted, isTrue);
    expect(prompted?.isMismatch, isTrue);
    expect(prompted?.previousFingerprintHex, '01:02:03');
    expect(prompted?.fingerprintHex, identity);
    expect(
      await repository.findFingerprint(profile.hostIdentifier, 'ssh-ed25519'),
      identity,
    );
  });

  test('prompt rejection leaves the previous pin unchanged', () async {
    final repository = InMemorySshKnownHostRepository();
    await repository.saveFingerprint(
      profile.hostIdentifier,
      'ssh-ed25519',
      '01:02:03',
    );
    final policy = SshHostKeyTrustPolicy(
      knownHostRepository: repository,
      onHostKeyPrompt: (_) async => false,
    );

    final accepted = await policy.verify(
      profile: profile,
      keyType: 'ssh-ed25519',
      fingerprint: Uint8List.fromList('SHA256:abc'.codeUnits),
    );

    expect(accepted, isFalse);
    expect(
      await repository.findFingerprint(profile.hostIdentifier, 'ssh-ed25519'),
      '01:02:03',
    );
  });
}
