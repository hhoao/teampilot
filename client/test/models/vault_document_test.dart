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
}
