import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/vault_document.dart';
import 'package:teampilot/models/vault_entry.dart';

void main() {
  test('round-trips entries and version', () {
    const document = VaultDocument(
      entries: [
        VaultEntry(
          id: '1',
          type: VaultEntryType.login,
          title: 'GitHub',
          fields: {'username': 'me', 'password': 'p'},
        ),
      ],
    );
    expect(VaultDocument.fromJson(document.toJson()), document);
  });

  test('rejects unknown document versions', () {
    expect(
      () => VaultDocument.fromJson({'version': 99, 'entries': []}),
      throwsA(isA<FormatException>()),
    );
  });

  test('legacy import marker round-trips and defaults to zero', () {
    const document = VaultDocument(legacyImportVersion: 1);
    expect(document.toJson()['legacyImportVersion'], 1);
    expect(VaultDocument.fromJson(document.toJson()).legacyImportVersion, 1);
    expect(
      const VaultDocument().legacyImportVersion,
      0,
      reason: 'old documents have no marker',
    );
    expect(
      VaultDocument.fromJson({'version': 1, 'entries': []}).legacyImportVersion,
      0,
    );
  });

  test('marker participates in document equality', () {
    expect(
      const VaultDocument(legacyImportVersion: 1),
      isNot(const VaultDocument(legacyImportVersion: 0)),
    );
  });
}
