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
}
