import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/vault_reference.dart';
import 'package:teampilot/services/vault/vault_reference_indexer.dart';

void main() {
  test('aggregates every source', () async {
    final indexer = VaultReferenceIndexer([
      (id) async => [
        VaultReference(
          kind: VaultReferenceKind.sshProfile,
          id: 'p1',
          label: 'Server',
        ),
      ],
      (id) async => [
        VaultReference(
          kind: VaultReferenceKind.appProvider,
          id: 'a1',
          label: 'Provider',
        ),
      ],
    ]);

    final refs = await indexer.referencesTo('v1');
    expect(refs.map((r) => r.id), containsAll(['p1', 'a1']));
  });

  test('an empty source list yields no references', () async {
    expect(await VaultReferenceIndexer(const []).referencesTo('v1'), isEmpty);
  });
}
