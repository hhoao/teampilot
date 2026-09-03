import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/app_provider_cubit.dart';
import 'package:teampilot/cubits/managed_provider_cubit.dart';
import 'package:teampilot/models/managed_provider.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/app_provider_repository.dart';
import 'package:teampilot/repositories/managed_provider_repository.dart';

import '../support/in_memory_filesystem.dart';

void main() {
  late InMemoryFilesystem fs;
  final usageRepoStub = _UsageRepoStub();
  late ManagedProviderRepository repo;

  setUp(() {
    fs = InMemoryFilesystem();
    repo = ManagedProviderRepository(
      fs: fs,
      configPath: '/tp/managed-providers.json',
      onProvidersDeleted: usageRepoStub.deleteMany,
    );
  });

  ManagedProvider entry({
    required String id,
    String source = 'cli:cursor-account',
  }) => ManagedProvider(
    id: id,
    name: 'Cursor Usage',
    kind: ManagedProviderKind.subscriptionQuota,
    adapterId: 'http-json',
    endpointConfig: ManagedProviderEndpointConfig(
      url: 'https://cursor.com/api/usage-summary',
      credentialSource: source,
      credentialName: 'Cookie',
      credentialTemplate: 'WorkosCursorSessionToken={accountId}::{accessToken}',
    ),
  );

  test('upsert rewrites legacy source to per-entry source', () async {
    final appCubit = AppProviderCubit(
      repository: AppProviderRepository(fs: fs, basePath: '/tp'),
      basePath: '/tp',
    );
    final cubit = ManagedProviderCubit(
      repository: repo,
      appProviderCubit: appCubit,
    );

    await cubit.upsert(entry(id: 'managed-1'));

    final saved = cubit.state.providerFor('managed-1')!;
    expect(
      saved.endpointConfig.credentialSource,
      'cli:cursor-mp-managed-1',
    );
    final cursorRows = appCubit.state.providersFor(CliTool.cursor);
    expect(
      cursorRows.any((row) => row.id == 'cursor-mp-managed-1'),
      isTrue,
    );
    await cubit.close();
    await appCubit.close();
  });

  test('upsert is idempotent for already per-entry sources', () async {
    await repo.save([entry(id: 'managed-2', source: 'cli:cursor-mp-managed-2')]);
    final appCubit = AppProviderCubit(
      repository: AppProviderRepository(fs: fs, basePath: '/tp'),
      basePath: '/tp',
    );
    final cubit = ManagedProviderCubit(
      repository: repo,
      appProviderCubit: appCubit,
    );
    await cubit.load();

    final loaded = cubit.state.providerFor('managed-2')!;
    expect(
      loaded.endpointConfig.credentialSource,
      'cli:cursor-mp-managed-2',
    );
    await cubit.close();
    await appCubit.close();
  });

  test('load migrates legacy source entries and ensures rows', () async {
    await repo.save([entry(id: 'managed-3')]);
    final appCubit = AppProviderCubit(
      repository: AppProviderRepository(fs: fs, basePath: '/tp'),
      basePath: '/tp',
    );
    final cubit = ManagedProviderCubit(
      repository: repo,
      appProviderCubit: appCubit,
    );
    await cubit.load();

    final migrated = cubit.state.providerFor('managed-3')!;
    expect(
      migrated.endpointConfig.credentialSource,
      'cli:cursor-mp-managed-3',
    );
    final persisted = await repo.load();
    expect(
      persisted.first.endpointConfig.credentialSource,
      'cli:cursor-mp-managed-3',
    );
    expect(
      appCubit.state.providersFor(CliTool.cursor)
          .any((row) => row.id == 'cursor-mp-managed-3'),
      isTrue,
    );
    await cubit.close();
    await appCubit.close();
  });
}

/// Minimal stub matching ManagedProviderUsageRepository.deleteMany.
class _UsageRepoStub {
  Future<void> deleteMany(List<String> ids) async {}
}
