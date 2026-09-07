import 'package:flutter_test/flutter_test.dart';

import 'package:teampilot/cubits/app_provider_cubit.dart';
import 'package:teampilot/cubits/managed_provider_cubit.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/models/managed_provider.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/app_provider_repository.dart';
import 'package:teampilot/repositories/managed_provider_repository.dart';
import 'package:teampilot/services/provider_usage/managed_provider_link_binding.dart';

import '../support/in_memory_filesystem.dart';

void main() {
  late InMemoryFilesystem fs;
  late ManagedProviderCubit managedCubit;
  late AppProviderCubit appCubit;

  setUp(() {
    fs = InMemoryFilesystem();
    final appRepo = AppProviderRepository(fs: fs, basePath: '/tp');
    final managedRepo = ManagedProviderRepository(
      fs: fs,
      configPath: '/tp/managed-providers.json',
      onProvidersDeleted: (_) async {},
    );
    appCubit = AppProviderCubit(repository: appRepo, basePath: '/tp');
    managedCubit = ManagedProviderCubit(
      repository: managedRepo,
      appProviderCubit: appCubit,
    );
  });

  tearDown(() async {
    await managedCubit.close();
    await appCubit.close();
  });

  ManagedProvider _entry(String id, String source) => ManagedProvider(
    id: id,
    name: 'Entry $id',
    kind: ManagedProviderKind.apiBalance,
    adapterId: 'http-json',
    endpointConfig: ManagedProviderEndpointConfig(credentialSource: source),
  );

  test('rejects a managed entry that links a provider which links back',
      () async {
    // Provider deepseek has credentialLink -> m1.
    await appCubit.upsertProvider(
      const AppProviderConfig(
        id: 'deepseek',
        cli: CliTool.claude,
        name: 'DeepSeek',
        category: AppProviderCategory.thirdParty,
        credentialLink: 'm1',
      ),
    );
    await managedCubit.upsert(
      _entry('m1', managedProviderLinkSourceValue(CliTool.claude, 'deepseek')),
    );
    // The cycle-forming upsert was rejected: entry not persisted.
    expect(managedCubit.state.providerFor('m1'), isNull);
    expect(managedCubit.state.errorCode, ManagedProviderErrorCode.saveFailed);
  });

  test('accepts a link when the provider has no back-link', () async {
    await appCubit.upsertProvider(
      const AppProviderConfig(
        id: 'deepseek',
        cli: CliTool.claude,
        name: 'DeepSeek',
        category: AppProviderCategory.thirdParty,
      ),
    );
    await managedCubit.upsert(
      _entry('m1', managedProviderLinkSourceValue(CliTool.claude, 'deepseek')),
    );
    expect(managedCubit.state.providerFor('m1'), isNotNull);
    expect(managedCubit.state.errorCode, isNull);
  });
}
