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

class _ThrowingSecureKeyValueStore implements SecureKeyValueStore {
  _ThrowingSecureKeyValueStore(this.error);

  final Object error;

  @override
  Future<void> delete(String key) async => throw error;

  @override
  Future<String?> read(String key) async => throw error;

  @override
  Future<void> write(String key, String value) async => throw error;
}

class _FailOnWriteSecureKeyValueStore implements SecureKeyValueStore {
  _FailOnWriteSecureKeyValueStore(this.failOnWrite, this.error);

  final int failOnWrite;
  final Object error;
  final values = <String, String>{};
  var writeCount = 0;

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    writeCount++;
    if (writeCount == failOnWrite) throw error;
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

      expect((await store.read(ref)).asMap(), {
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

      expect((await store.read(ref)).isEmpty, isTrue);
      expect(await store.readMasked(ref), isEmpty);
    },
  );

  test('asMap remains immutable and redacts values from toString', () async {
    final backend = _FakeSecureKeyValueStore();
    final store = ManagedProviderSecretStore(backend);
    const secret = 'scope-map-secret';

    await store.write('managed-provider:p1', {'apiKey': secret});
    final scope = await store.read('managed-provider:p1');
    final values = scope.asMap();

    expect(values['apiKey'], secret);
    expect(values.toString(), isNot(contains(secret)));
    expect(scope.toString(), isNot(contains(secret)));
    expect(() => values['apiKey'] = 'replacement', throwsUnsupportedError);
  });

  test(
    'normalizes whitespace and rejects unsafe namespace components',
    () async {
      final backend = _FakeSecureKeyValueStore();
      final store = ManagedProviderSecretStore(backend);

      await store.write(' managed-provider:p1 ', {' apiKey ': 'secret'});

      expect((await store.read('managed-provider:p1')).asMap(), {
        'apiKey': 'secret',
      });
      expect(
        backend.values.keys,
        contains('teampilot.managed_provider.v1.managed-provider:p1.apiKey'),
      );

      for (final reference in [
        '',
        '  ',
        'managed-provider/p1',
        'managed-provider\\p1',
        'managed-provider.p1',
        'managed-provider\np1',
      ]) {
        await expectLater(
          store.write(reference, {'apiKey': 'secret'}),
          throwsA(isA<ManagedProviderCredentialError>()),
        );
      }

      for (final field in [
        '',
        '  ',
        'api.key',
        'api/key',
        'api\\key',
        'api\nkey',
        '__fields',
      ]) {
        await expectLater(
          store.write('managed-provider:p2', {field: 'secret'}),
          throwsA(isA<ManagedProviderCredentialError>()),
        );
      }
    },
  );

  test(
    'does not collide when references normalize to the same namespace',
    () async {
      final backend = _FakeSecureKeyValueStore();
      final store = ManagedProviderSecretStore(backend);

      await store.write('managed-provider:p1', {'apiKey': 'first'});
      await store.write(' managed-provider:p1 ', {'apiKey': 'second'});

      expect((await store.read('managed-provider:p1')).asMap(), {
        'apiKey': 'second',
      });
      expect(
        backend.values.keys.where((key) => key.contains('managed-provider:p1')),
        hasLength(3),
      );
    },
  );

  test(
    'fails safely when the manifest is missing during delete or replace',
    () async {
      final backend = _FakeSecureKeyValueStore();
      final store = ManagedProviderSecretStore(backend);
      const ref = 'managed-provider:p1';
      const key = 'teampilot.managed_provider.v1.$ref.apiKey';
      const manifest = 'teampilot.managed_provider.v1.$ref.__fields';

      await store.write(ref, {'apiKey': 'old-secret'});
      backend.values.remove(manifest);

      await expectLater(
        store.delete(ref),
        throwsA(isA<ManagedProviderCredentialError>()),
      );
      await expectLater(
        store.write(ref, {'apiKey': 'new-secret'}),
        throwsA(isA<ManagedProviderCredentialError>()),
      );
      expect(backend.values[key], 'old-secret');
    },
  );

  test(
    'fails safely when the manifest is corrupt during delete or replace',
    () async {
      final backend = _FakeSecureKeyValueStore();
      final store = ManagedProviderSecretStore(backend);
      const ref = 'managed-provider:p1';
      const key = 'teampilot.managed_provider.v1.$ref.apiKey';
      const manifest = 'teampilot.managed_provider.v1.$ref.__fields';

      await store.write(ref, {'apiKey': 'old-secret'});
      backend.values[manifest] = '{not-json';

      await expectLater(
        store.delete(ref),
        throwsA(isA<ManagedProviderCredentialError>()),
      );
      await expectLater(
        store.write(ref, {'apiKey': 'new-secret'}),
        throwsA(isA<ManagedProviderCredentialError>()),
      );
      expect(backend.values[key], 'old-secret');
    },
  );

  test(
    'delete is idempotent for a never-initialized credential reference',
    () async {
      final backend = _FakeSecureKeyValueStore();
      final store = ManagedProviderSecretStore(backend);

      await store.delete('never-initialized');

      expect(backend.values, isEmpty);
    },
  );

  test('rolls back secret fields when a multi-step write fails', () async {
    const secret = 'rollback-secret';
    final backend = _FailOnWriteSecureKeyValueStore(
      4,
      StateError('backend failed while handling $secret'),
    );
    final store = ManagedProviderSecretStore(backend);

    final error = await captureException(
      () => store.write('managed-provider:p1', {
        'apiKey': secret,
        'token': 'second-$secret',
      }),
    );

    expect(error, isA<ManagedProviderCredentialError>());
    expect(error.toString(), isNot(contains(secret)));
    expect(backend.values, isEmpty);
  });

  test('wraps backend failures without exposing backend details', () async {
    const secret = 'backend-secret-value';
    final rawError = StateError('backend failed for $secret');
    final store = ManagedProviderSecretStore(
      _ThrowingSecureKeyValueStore(rawError),
    );

    final error = await captureException(
      () => store.read('managed-provider:p1'),
    );

    expect(error, isA<ManagedProviderCredentialError>());
    expect(error.toString(), isNot(contains(secret)));
    expect(error.toString(), isNot(contains(rawError.toString())));
  });

  test(
    'resolver returns only request-scoped credentials for a provider',
    () async {
      final backend = _FakeSecureKeyValueStore();
      final store = ManagedProviderSecretStore(backend);
      await store.write('managed-provider:p1', {'apiKey': 'request-secret'});
      final resolver = ManagedProviderCredentialResolver(store);

      final credentials = await resolver.resolve(_provider());

      expect(credentials, isA<ManagedProviderCredentialScope>());
      expect(credentials, isNotNull);
      expect(credentials!.valueFor('apiKey'), 'request-secret');
      expect(credentials.toString(), isNot(contains('request-secret')));
      expect(credentials.asMap(), {'apiKey': 'request-secret'});
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
      final provider = _provider().copyWith(
        endpointConfig: ManagedProviderEndpointConfig(
          fieldMappings: {'apiKey': secret, 'safe': 'data.safe'},
        ),
        unknownFields: {
          'futureCredential': 'Bearer $secret',
          'X-Api-Key': secret,
        },
      );
      final json = provider.toJson();
      final encoded = jsonEncode(json);

      expect(json['credentialRef'], 'managed-provider:p1');
      expect(encoded, isNot(contains(secret)));
      expect(encoded, isNot(contains('Bearer')));
      expect(json.keys, isNot(contains('apiKey')));
      expect(json.keys, isNot(contains('token')));
    },
  );
}

Future<Object> captureException<T>(Future<T> Function() action) async {
  try {
    await action();
    fail('Expected action to throw');
  } on Object catch (error) {
    return error;
  }
}
