import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/services/github/github_credentials_store.dart';

class ThrowingSecureKeyValueStore implements SecureKeyValueStore {
  ThrowingSecureKeyValueStore(
    this.inner, {
    required this.shouldThrowOnWrite,
  });

  final SecureKeyValueStore inner;
  final bool Function(String key) shouldThrowOnWrite;

  @override
  Future<void> delete(String key) => inner.delete(key);

  @override
  Future<String?> read(String key) => inner.read(key);

  @override
  Future<void> write(String key, String value) async {
    if (shouldThrowOnWrite(key)) {
      throw StateError('write failed for $key');
    }
    await inner.write(key, value);
  }
}

class InMemorySecureKeyValueStore implements SecureKeyValueStore {
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

void main() {
  test('saveOAuth round-trips token, login, and source', () async {
    final store = GithubCredentialsStore(kv: InMemorySecureKeyValueStore());
    await store.saveOAuth(token: 'gho_test', login: 'alice');

    final snapshot = await store.readStored();
    expect(snapshot?.token, 'gho_test');
    expect(snapshot?.login, 'alice');
    expect(snapshot?.source, GithubCredentialSource.oauth);
  });

  test('savePat round-trips token and source', () async {
    final store = GithubCredentialsStore(kv: InMemorySecureKeyValueStore());
    await store.savePat('ghp_test', login: 'bob');

    final snapshot = await store.readStored();
    expect(snapshot?.token, 'ghp_test');
    expect(snapshot?.login, 'bob');
    expect(snapshot?.source, GithubCredentialSource.pat);
  });

  test('savePat without login stores token only', () async {
    final store = GithubCredentialsStore(kv: InMemorySecureKeyValueStore());
    await store.savePat('ghp_test');

    final snapshot = await store.readStored();
    expect(snapshot?.token, 'ghp_test');
    expect(snapshot?.login, isNull);
    expect(snapshot?.source, GithubCredentialSource.pat);
  });

  test('clearStored removes stored credentials', () async {
    final store = GithubCredentialsStore(kv: InMemorySecureKeyValueStore());
    await store.savePat('ghp_test', login: 'alice');
    await store.clearStored();

    expect(await store.readStored(), isNull);
  });

  test('resolveToken prefers stored token over env fallback', () async {
    final store = GithubCredentialsStore(
      kv: InMemorySecureKeyValueStore(),
      readEnvToken: () => 'ghp_env',
    );
    await store.savePat('ghp_saved');

    expect(await store.resolveToken(), 'ghp_saved');
  });

  test('resolveToken falls back to env when store is empty', () async {
    final store = GithubCredentialsStore(
      kv: InMemorySecureKeyValueStore(),
      readEnvToken: () => 'ghp_env',
    );

    expect(await store.resolveToken(), 'ghp_env');
  });

  test('clearStored leaves env resolvable', () async {
    final store = GithubCredentialsStore(
      kv: InMemorySecureKeyValueStore(),
      readEnvToken: () => 'ghp_env',
    );
    await store.savePat('ghp_saved');
    await store.clearStored();

    expect(await store.resolveToken(), 'ghp_env');
  });

  test('legacy hub publish token migrates once into pat storage', () async {
    final kv = InMemorySecureKeyValueStore();
    kv.values['teampilot.hub_publish.v1.github_token'] = 'ghp_legacy';
    final store = GithubCredentialsStore(kv: kv);

    expect(await store.resolveToken(), 'ghp_legacy');

    final snapshot = await store.readStored();
    expect(snapshot?.token, 'ghp_legacy');
    expect(snapshot?.source, GithubCredentialSource.pat);
    expect(kv.values.containsKey('teampilot.hub_publish.v1.github_token'), isFalse);

    // Second read does not re-migrate or fail.
    expect(await store.resolveToken(), 'ghp_legacy');
  });

  test('legacy migration retries after storage write failure', () async {
    final inner = InMemorySecureKeyValueStore();
    inner.values['teampilot.hub_publish.v1.github_token'] = 'ghp_legacy';
    var failWrites = true;
    final kv = ThrowingSecureKeyValueStore(
      inner,
      shouldThrowOnWrite: (_) => failWrites,
    );
    final store = GithubCredentialsStore(kv: kv);

    await expectLater(
      store.migrateLegacyHubPublishTokenIfNeeded(),
      throwsA(isA<StateError>()),
    );
    expect(
      inner.values.containsKey('teampilot.hub_publish.v1.github_token'),
      isTrue,
    );
    expect(inner.values.containsKey('teampilot.github.v1.token'), isFalse);

    failWrites = false;
    await store.migrateLegacyHubPublishTokenIfNeeded();

    expect(await store.resolveToken(), 'ghp_legacy');
    expect(
      inner.values.containsKey('teampilot.hub_publish.v1.github_token'),
      isFalse,
    );
  });

  test('migrateLegacyHubPublishTokenIfNeeded is idempotent', () async {
    final kv = InMemorySecureKeyValueStore();
    kv.values['teampilot.hub_publish.v1.github_token'] = 'ghp_legacy';
    final store = GithubCredentialsStore(kv: kv);

    await store.migrateLegacyHubPublishTokenIfNeeded();
    await store.migrateLegacyHubPublishTokenIfNeeded();

    expect(await store.readStored(), isNotNull);
    expect(kv.values.containsKey('teampilot.hub_publish.v1.github_token'), isFalse);
  });
}
