import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/vault/provider_credential_link.dart';

void main() {
  test('parses vault entry links', () {
    expect(vaultEntryIdFromCredentialLink('vault:a'), 'a');
    expect(vaultEntryIdFromCredentialLink('  vault:b  '), 'b');
  });

  test('rejects other links and empty ids', () {
    expect(vaultEntryIdFromCredentialLink('managed-1'), isNull);
    expect(vaultEntryIdFromCredentialLink('vault:'), isNull);
    expect(vaultEntryIdFromCredentialLink(''), isNull);
  });
}
