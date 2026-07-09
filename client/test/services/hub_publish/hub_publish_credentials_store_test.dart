import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/services/hub_publish/hub_publish_credentials_store.dart';

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
  test('round-trips github token', () async {
    final store = HubPublishCredentialsStore(kv: InMemorySecureKeyValueStore());
    await store.saveToken('ghp_test');
    expect(await store.readToken(), 'ghp_test');
    await store.clearToken();
    expect(await store.readToken(), isNull);
  });

  test('resolveToken prefers stored token over env fallback', () async {
    final store = HubPublishCredentialsStore(
      kv: InMemorySecureKeyValueStore(),
      readEnvToken: () => 'ghp_env',
    );
    await store.saveToken('ghp_saved');
    expect(await store.resolveToken(), 'ghp_saved');
  });

  test('resolveToken falls back to env when store is empty', () async {
    final store = HubPublishCredentialsStore(
      kv: InMemorySecureKeyValueStore(),
      readEnvToken: () => 'ghp_env',
    );
    expect(await store.resolveToken(), 'ghp_env');
  });
}
