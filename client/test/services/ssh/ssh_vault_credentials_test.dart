import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/services/ssh/ssh_credentials_resolver.dart';

void main() {
  const profile = SshProfile(
    id: 'p1',
    name: 'Server',
    host: 'example.com',
    username: 'u',
    vaultEntryId: 'v1',
  );

  test('vault entry wins over the legacy store', () async {
    final resolved = await resolveSshCredentials(
      profile,
      vault: (entryId, field) async =>
          entryId == 'v1' && field == 'password' ? 'from-vault' : null,
      legacyPassword: (_) async => 'from-keychain',
      legacyPrivateKey: (_) async => 'legacy-pem',
      legacyPassphrase: (_) async => 'legacy-pass',
    );
    expect(resolved.password, 'from-vault');
    expect(resolved.privateKey, isNull);
  });

  test('legacy store is used when no vault entry is linked', () async {
    const legacy = SshProfile(
      id: 'p2',
      name: 'Legacy',
      host: 'example.com',
      username: 'u',
    );
    final resolved = await resolveSshCredentials(
      legacy,
      vault: (_, _) async => 'from-vault',
      legacyPassword: (_) async => 'from-keychain',
      legacyPrivateKey: (_) async => 'legacy-pem',
      legacyPassphrase: (_) async => 'legacy-pass',
    );
    expect(resolved.password, 'from-keychain');
  });

  test('vault private key and passphrase resolve together', () async {
    const keyProfile = SshProfile(
      id: 'p3',
      name: 'Key',
      host: 'example.com',
      username: 'u',
      authType: SshAuthType.privateKey,
      vaultEntryId: 'v1',
    );
    final resolved = await resolveSshCredentials(
      keyProfile,
      vault: (entryId, field) async => switch (field) {
        'privateKey' => 'vault-pem',
        'passphrase' => 'vault-pass',
        _ => null,
      },
      legacyPassword: (_) async => null,
      legacyPrivateKey: (_) async => null,
      legacyPassphrase: (_) async => null,
    );
    expect(resolved.privateKey, 'vault-pem');
    expect(resolved.passphrase, 'vault-pass');
  });
}
