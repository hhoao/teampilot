import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/models/managed_provider.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/app_provider_repository.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/services/provider_usage/managed_provider_link_binding.dart';
import 'package:teampilot/services/provider_usage/managed_provider_secret_store.dart';

import '../../support/in_memory_filesystem.dart';

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

ManagedProvider _linkedEntry(CliTool cli, String providerId) =>
    ManagedProvider(
      id: 'm1',
      name: 'M1',
      kind: ManagedProviderKind.apiBalance,
      adapterId: 'http-json',
      endpointConfig: ManagedProviderEndpointConfig(
        credentialSource: managedProviderLinkSourceValue(cli, providerId),
        credentialField: 'apiKey',
      ),
    );

ManagedProvider _secretEntry() => ManagedProvider(
  id: 'm2',
  name: 'M2',
  kind: ManagedProviderKind.apiBalance,
  adapterId: 'http-json',
  credentialRef: 'managed-provider:m2',
  endpointConfig: ManagedProviderEndpointConfig(
    credentialField: 'apiKey',
  ),
);

void main() {
  late InMemoryFilesystem fs;
  late AppProviderRepository repo;

  setUp(() {
    fs = InMemoryFilesystem();
    repo = AppProviderRepository(fs: fs, basePath: '/tp');
  });

  Future<void> seedProvider(
    CliTool cli,
    String id,
    String apiKey, {
    bool writeKey = true,
  }) async {
    final provider = AppProviderConfig(
      id: id,
      cli: cli,
      name: 'Test',
      category: AppProviderCategory.thirdParty,
      apiKey: writeKey ? apiKey : '',
    );
    await fs.ensureDir('/tp/providers/${cli.value}');
    await fs.writeString(
      '/tp/providers/${cli.value}/providers.json',
      '{"providers":{"$id":${jsonEncode(provider.toJson())}}}',
    );
  }

  test('resolves provider source to the referenced apiKey', () async {
    await seedProvider(CliTool.claude, 'deepseek', 'sk-123');
    final resolver = ManagedProviderCredentialResolver(
      ManagedProviderSecretStore(_FakeSecureKeyValueStore()),
      appProviders: repo,
    );
    final scope = await resolver.resolve(
      _linkedEntry(CliTool.claude, 'deepseek'),
    );
    expect(scope, isNotNull);
    expect(scope!.valueFor('apiKey'), 'sk-123');
  });

  test('missing provider or empty key resolves to null', () async {
    final resolver = ManagedProviderCredentialResolver(
      ManagedProviderSecretStore(_FakeSecureKeyValueStore()),
      appProviders: repo,
    );
    // No provider row at all.
    expect(await resolver.resolve(_linkedEntry(CliTool.claude, 'nope')), isNull);
    // Provider row exists but key is blank.
    await seedProvider(CliTool.claude, 'empty', '', writeKey: false);
    expect(
      await resolver.resolve(_linkedEntry(CliTool.claude, 'empty')),
      isNull,
    );
  });

  test('secret sources still resolve through the secret store', () async {
    final kv = _FakeSecureKeyValueStore();
    const ref = 'managed-provider:m2';
    await kv.write('teampilot.managed_provider.v1.$ref.__fields', '["apiKey"]');
    await kv.write('teampilot.managed_provider.v1.$ref.__initialized', '1');
    await kv.write('teampilot.managed_provider.v1.$ref.apiKey', 'sk-secret');
    final resolver = ManagedProviderCredentialResolver(
      ManagedProviderSecretStore(kv),
      appProviders: repo,
    );
    final scope = await resolver.resolve(_secretEntry());
    expect(scope, isNotNull);
    expect(scope!.valueFor('apiKey'), 'sk-secret');
  });

  test('null appProviders repository leaves provider sources unresolved',
      () async {
    final resolver = ManagedProviderCredentialResolver(
      ManagedProviderSecretStore(_FakeSecureKeyValueStore()),
    );
    expect(
      await resolver.resolve(_linkedEntry(CliTool.claude, 'deepseek')),
      isNull,
    );
  });
}
