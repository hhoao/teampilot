import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/services/provider_usage/managed_provider_credential_transaction.dart';
import 'package:teampilot/services/provider_usage/managed_provider_secret_store.dart';

class _MemorySecureKeyValueStore implements SecureKeyValueStore {
  final values = <String, String>{};
  var reads = 0;
  var writes = 0;
  var deletes = 0;

  @override
  Future<void> delete(String key) async {
    deletes++;
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async {
    reads++;
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    writes++;
    values[key] = value;
  }
}

void expectScope(ProviderCredentialScope scope, Map<String, String> expected) {
  expect(scope.fields.toSet(), expected.keys.toSet());
  for (final entry in expected.entries) {
    expect(scope.valueFor(entry.key), entry.value);
  }
}

void main() {
  test('blank secret does not touch storage and persists provider', () async {
    final backend = _MemorySecureKeyValueStore();
    final transaction = ManagedProviderCredentialTransaction(
      ManagedProviderSecretStore(backend),
    );
    var persisted = false;

    final result = await transaction.run<String>(
      credentialRef: 'managed-provider:p1',
      nextValues: const {},
      persistProvider: () async {
        persisted = true;
        return 'saved';
      },
    );

    expect(result, 'saved');
    expect(persisted, isTrue);
    expect(backend.reads, 0);
    expect(backend.writes, 0);
    expect(backend.deletes, 0);
  });

  test('restores an old secret when provider persistence fails', () async {
    final backend = _MemorySecureKeyValueStore();
    final store = ManagedProviderSecretStore(backend);
    const ref = 'managed-provider:p1';
    await store.write(ref, {'apiKey': 'old-secret'});
    final transaction = ManagedProviderCredentialTransaction(store);

    await expectLater(
      transaction.run<void>(
        credentialRef: ref,
        nextValues: const {'apiKey': 'new-secret'},
        persistProvider: () async => throw StateError('save failed'),
      ),
      throwsA(isA<StateError>()),
    );

    expectScope(await store.read(ref), {'apiKey': 'old-secret'});
    expect(backend.values.toString(), isNot(contains('new-secret')));
  });

  test(
    'deletes a new credential ref when provider persistence fails',
    () async {
      final backend = _MemorySecureKeyValueStore();
      final store = ManagedProviderSecretStore(backend);
      const ref = 'managed-provider:p1';
      final transaction = ManagedProviderCredentialTransaction(store);

      await expectLater(
        transaction.run<void>(
          credentialRef: ref,
          nextValues: const {'apiKey': 'new-secret'},
          persistProvider: () async => throw StateError('save failed'),
        ),
        throwsA(isA<StateError>()),
      );

      expect((await store.read(ref)).isEmpty, isTrue);
      expect(backend.values.toString(), isNot(contains('new-secret')));
    },
  );
}
