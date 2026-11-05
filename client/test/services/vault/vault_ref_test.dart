import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/vault/vault_ref.dart';

void main() {
  test('parses vault and managed references', () {
    final vault = VaultRef.parse(' vault:entry-1 ');
    expect(vault, isA<VaultEntryRef>());
    expect((vault as VaultEntryRef).entryId, 'entry-1');
    expect(vault.link, 'vault:entry-1');

    final managed = VaultRef.parse('managed-1');
    expect(managed, isA<ManagedProviderRef>());
    expect((managed as ManagedProviderRef).providerId, 'managed-1');
  });

  test('rejects empty and empty-id links', () {
    expect(VaultRef.parse(''), isNull);
    expect(VaultRef.parse('   '), isNull);
    expect(VaultRef.parse('vault:'), isNull);
    expect(VaultRef.parse('vault:   '), isNull);
    expect(vaultEntryIdFromCredentialLink('managed-1'), isNull);
  });
}
