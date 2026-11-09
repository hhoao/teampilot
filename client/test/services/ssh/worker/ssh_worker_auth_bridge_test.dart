import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/ssh_known_host_repository.dart';
import 'package:teampilot/services/ssh/worker/ssh_worker_auth_bridge.dart';
import 'package:teampilot/services/ssh/worker/ssh_worker_protocol.dart';

const testProfile = SshProfile(
  id: 'p1',
  name: 'Test profile',
  host: 'example.test',
  username: 'tester',
);

void main() {
  test(
    'host-key challenge delegates to trust policy and returns decision',
    () async {
      final prompts = <HostKeyPromptInfo>[];
      final bridge = SshWorkerAuthBridge(
        credentialStore: InMemorySshCredentialStore(),
        knownHostRepository: InMemorySshKnownHostRepository(),
        onHostKeyPrompt: (info) async {
          prompts.add(info);
          return true;
        },
      );

      final reply = await bridge.replyTo(
        testProfile,
        SshWorkerAuthChallenge.hostKey(
          requestId: 'host-key-1',
          profileId: testProfile.id,
          keyType: 'ssh-ed25519',
          fingerprint: Uint8List.fromList([1, 2, 3]),
        ),
      );

      expect(reply.accepted, isTrue);
      expect(prompts.single.profile.id, testProfile.id);
    },
  );

  test('credential challenge reply never logs secret material', () async {
    final store = InMemorySshCredentialStore();
    await store.savePassword(testProfile.id, 'secret');
    await store.savePrivateKey(testProfile.id, 'private-key-material');
    final diagnostics = <String>[];
    final bridge = SshWorkerAuthBridge(
      credentialStore: store,
      knownHostRepository: InMemorySshKnownHostRepository(),
      log: diagnostics.add,
    );

    final password = await bridge.replyTo(
      testProfile,
      SshWorkerAuthChallenge.password(
        requestId: 'password-1',
        profileId: testProfile.id,
      ),
    );
    final privateKey = await bridge.replyTo(
      testProfile,
      SshWorkerAuthChallenge.privateKey(
        requestId: 'private-key-1',
        profileId: testProfile.id,
      ),
    );

    expect(password.secretValue, 'secret');
    expect(privateKey.secretValue, 'private-key-material');
    expect(diagnostics, everyElement(isNot(contains('secret'))));
    expect(diagnostics, everyElement(isNot(contains('private-key-material'))));
  });

  test('vault entry overrides legacy credentials', () async {
    final store = InMemorySshCredentialStore();
    await store.savePassword(testProfile.id, 'legacy-secret');
    final requested = <String>[];
    final bridge = SshWorkerAuthBridge(
      credentialStore: store,
      knownHostRepository: InMemorySshKnownHostRepository(),
      vault: (entryId, field) async {
        requested.add('$entryId/$field');
        return field == 'password' ? 'vault-secret' : null;
      },
    );
    final profile = testProfile.copyWith(vaultEntryId: 'vault-1');

    final reply = await bridge.replyTo(
      profile,
      SshWorkerAuthChallenge.password(
        requestId: 'password-vault',
        profileId: profile.id,
      ),
    );

    expect(reply.secretValue, 'vault-secret');
    expect(requested, ['vault-1/password']);
  });

  test('owner-linked vault entry supplies credentials when catalog row has no '
      'vaultEntryId', () async {
    final store = InMemorySshCredentialStore();
    final requested = <String>[];
    final ownerLookups = <String>[];
    final bridge = SshWorkerAuthBridge(
      credentialStore: store,
      knownHostRepository: InMemorySshKnownHostRepository(),
      vault: (entryId, field) async {
        requested.add('$entryId/$field');
        return field == 'password' ? 'vault-secret' : null;
      },
      vaultEntryIdFor: (profileId) async {
        ownerLookups.add(profileId);
        return 'owner-entry-1';
      },
    );

    final reply = await bridge.replyTo(
      testProfile,
      SshWorkerAuthChallenge.password(
        requestId: 'password-owner',
        profileId: testProfile.id,
      ),
    );

    expect(reply.secretValue, 'vault-secret');
    expect(requested, ['owner-entry-1/password']);
    expect(ownerLookups, [testProfile.id]);
  });

  test('explicit vaultEntryId skips the owner lookup', () async {
    final requested = <String>[];
    final ownerLookups = <String>[];
    final bridge = SshWorkerAuthBridge(
      credentialStore: InMemorySshCredentialStore(),
      knownHostRepository: InMemorySshKnownHostRepository(),
      vault: (entryId, field) async {
        requested.add('$entryId/$field');
        return 'vault-secret';
      },
      vaultEntryIdFor: (profileId) async {
        ownerLookups.add(profileId);
        return 'owner-entry-1';
      },
    );
    final profile = testProfile.copyWith(vaultEntryId: 'explicit-entry');

    final reply = await bridge.replyTo(
      profile,
      SshWorkerAuthChallenge.password(
        requestId: 'password-explicit',
        profileId: profile.id,
      ),
    );

    expect(reply.secretValue, 'vault-secret');
    expect(requested, ['explicit-entry/password']);
    expect(ownerLookups, isEmpty);
  });

  test(
    'falls back to legacy keychain when no owner vault entry exists',
    () async {
      final store = InMemorySshCredentialStore();
      await store.savePassword(testProfile.id, 'legacy-secret');
      var vaultReads = 0;
      final bridge = SshWorkerAuthBridge(
        credentialStore: store,
        knownHostRepository: InMemorySshKnownHostRepository(),
        vault: (_, __) async {
          vaultReads++;
          return 'vault-secret';
        },
        vaultEntryIdFor: (_) async => null,
      );

      final reply = await bridge.replyTo(
        testProfile,
        SshWorkerAuthChallenge.password(
          requestId: 'password-legacy',
          profileId: testProfile.id,
        ),
      );

      expect(reply.secretValue, 'legacy-secret');
      expect(vaultReads, 0);
    },
  );

  test('falls back to legacy keychain when the owner lookup fails', () async {
    final store = InMemorySshCredentialStore();
    await store.savePassword(testProfile.id, 'legacy-secret');
    final bridge = SshWorkerAuthBridge(
      credentialStore: store,
      knownHostRepository: InMemorySshKnownHostRepository(),
      vault: (_, __) async => 'vault-secret',
      vaultEntryIdFor: (_) async => throw StateError('vault locked'),
    );

    final reply = await bridge.replyTo(
      testProfile,
      SshWorkerAuthChallenge.password(
        requestId: 'password-owner-failure',
        profileId: testProfile.id,
      ),
    );

    expect(reply.secretValue, 'legacy-secret');
  });

  test('owner-resolved entry supplies private key and passphrase', () async {
    final requested = <String>[];
    final bridge = SshWorkerAuthBridge(
      credentialStore: InMemorySshCredentialStore(),
      knownHostRepository: InMemorySshKnownHostRepository(),
      vault: (entryId, field) async {
        requested.add('$entryId/$field');
        return switch (field) {
          'privateKey' => 'pem-material',
          'passphrase' => 'key-passphrase',
          _ => null,
        };
      },
      vaultEntryIdFor: (_) async => 'owner-entry-1',
    );
    final profile = testProfile.copyWith(authType: SshAuthType.privateKey);

    final privateKey = await bridge.replyTo(
      profile,
      SshWorkerAuthChallenge.privateKey(
        requestId: 'private-key-owner',
        profileId: profile.id,
      ),
    );
    final passphrase = await bridge.replyTo(
      profile,
      SshWorkerAuthChallenge.privateKeyPassphrase(
        requestId: 'passphrase-owner',
        profileId: profile.id,
      ),
    );

    expect(privateKey.secretValue, 'pem-material');
    expect(passphrase.secretValue, 'key-passphrase');
    expect(requested, ['owner-entry-1/privateKey', 'owner-entry-1/passphrase']);
  });

  test('dial target is resolved again for each worker generation', () async {
    var port = 4000;
    final bridge = SshWorkerAuthBridge(
      credentialStore: InMemorySshCredentialStore(),
      knownHostRepository: InMemorySshKnownHostRepository(),
      dialTargetResolver: (_) async =>
          (address: InternetAddress.loopbackIPv4, port: port++),
    );

    final first = await bridge.dialTargetFor(testProfile);
    final second = await bridge.dialTargetFor(testProfile);

    expect(first.port, 4000);
    expect(second.port, 4001);
  });
}
