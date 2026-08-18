import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/managed_provider.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/services/provider_usage/managed_provider_secret_store.dart';

class _FakeSecureKeyValueStore implements SecureKeyValueStore {
  final values = <String, String>{};

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

ManagedProvider _provider({String? credentialRef = 'managed-provider:p1'}) =>
    ManagedProvider(
      id: 'p1',
      name: 'Example',
      kind: ManagedProviderKind.apiBalance,
      adapterId: 'example',
      credentialRef: credentialRef,
    );

void main() {
  test('writes credentials under a managed-provider namespace', () async {
    final backend = _FakeSecureKeyValueStore();
    final store = ManagedProviderSecretStore(backend);

    await store.write('managed-provider:p1', {
      'apiKey': 'provider-secret',
      'account': 'billing-account',
    });

    expect(
      backend
          .values['teampilot.managed_provider.v1.managed-provider:p1.apiKey'],
      'provider-secret',
    );
    expect(
      backend.values.keys,
      everyElement(startsWith('teampilot.managed_provider.v1.')),
    );
  });

  test(
    'reads, deletes, and masks credential values without exposing them',
    () async {
      final backend = _FakeSecureKeyValueStore();
      final store = ManagedProviderSecretStore(backend);
      const ref = 'managed-provider:p1';
      const secret = 'provider-secret-value';

      await store.write(ref, {'apiKey': secret, 'token': 'another-secret'});

      expect(await store.read(ref), {
        'apiKey': secret,
        'token': 'another-secret',
      });
      final masked = await store.readMasked(ref);
      expect(masked, {
        'apiKey': ManagedProviderSecretStore.maskedValue,
        'token': ManagedProviderSecretStore.maskedValue,
      });
      expect(masked.toString(), isNot(contains(secret)));

      await store.delete(ref);

      expect(await store.read(ref), isEmpty);
      expect(await store.readMasked(ref), isEmpty);
    },
  );

  test(
    'resolver returns only request-scoped credentials for a provider',
    () async {
      final backend = _FakeSecureKeyValueStore();
      final store = ManagedProviderSecretStore(backend);
      await store.write('managed-provider:p1', {'apiKey': 'request-secret'});
      final resolver = ManagedProviderCredentialResolver(store);

      final credentials = await resolver.resolve(_provider());

      expect(credentials, {'apiKey': 'request-secret'});
      expect(credentials, isNotNull);
    },
  );

  test('resolver returns null for missing credential references', () async {
    final resolver = ManagedProviderCredentialResolver(
      ManagedProviderSecretStore(_FakeSecureKeyValueStore()),
    );

    expect(await resolver.resolve(_provider(credentialRef: null)), isNull);
    expect(
      await resolver.resolve(_provider(credentialRef: 'missing-ref')),
      isNull,
    );
  });

  test(
    'managed provider JSON contains the reference but never secret values',
    () {
      const secret = 'model-must-not-contain-this';
      final json = _provider().toJson();

      expect(json['credentialRef'], 'managed-provider:p1');
      expect(jsonEncode(json), isNot(contains(secret)));
      expect(json.keys, isNot(contains('apiKey')));
      expect(json.keys, isNot(contains('token')));
    },
  );
}
