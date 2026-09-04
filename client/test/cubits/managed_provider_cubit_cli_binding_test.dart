import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/app_provider_cubit.dart';
import 'package:teampilot/cubits/managed_provider_cubit.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/models/managed_provider.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/app_provider_repository.dart';
import 'package:teampilot/repositories/managed_provider_repository.dart';
import 'package:teampilot/services/provider_usage/managed_provider_cli_row_janitor.dart';

import '../support/in_memory_filesystem.dart';

void main() {
  late InMemoryFilesystem fs;
  late ManagedProviderRepository repo;
  late _UsageRepoStub usageRepo;

  setUp(() {
    fs = InMemoryFilesystem();
    usageRepo = _UsageRepoStub();
    repo = ManagedProviderRepository(
      fs: fs,
      configPath: '/tp/managed-providers.json',
      onProvidersDeleted: usageRepo.deleteMany,
    );
  });

  ManagedProvider _entry({
    required String id,
    String source = 'cli:cursor',
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

  AppProviderCubit _appCubit() => AppProviderCubit(
    repository: AppProviderRepository(fs: fs, basePath: '/tp'),
    basePath: '/tp',
  );

  test('upsert expands an intent source to the per-entry source', () async {
    final appCubit = _appCubit();
    final cubit = ManagedProviderCubit(
      repository: repo,
      appProviderCubit: appCubit,
    );

    await cubit.upsert(_entry(id: 'managed-1'));

    final saved = cubit.state.providerFor('managed-1')!;
    expect(
      saved.endpointConfig.credentialSource,
      'cli:cursor-mp-managed-1',
    );
    expect(
      appCubit.state
          .providersFor(CliTool.cursor)
          .any((row) => row.id == 'cursor-mp-managed-1'),
      isTrue,
    );
    await cubit.close();
    await appCubit.close();
  });

  test('upsert leaves already per-entry sources unchanged', () async {
    await repo.save([
      _entry(id: 'managed-2', source: 'cli:cursor-mp-managed-2'),
    ]);
    final appCubit = _appCubit();
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

  test('load leaves legacy-source entries untouched and un-migrated', () async {
    await repo.save([_entry(id: 'managed-3', source: 'cli:cursor-account')]);
    final appCubit = _appCubit();
    final cubit = ManagedProviderCubit(
      repository: repo,
      appProviderCubit: appCubit,
    );
    await cubit.load();

    final loaded = cubit.state.providerFor('managed-3')!;
    // No migration, no row ensure: the entry stays exactly as on disk and
    // no dedicated row is created for it.
    expect(
      loaded.endpointConfig.credentialSource,
      'cli:cursor-account',
    );
    expect(
      appCubit.state
          .providersFor(CliTool.cursor)
          .any((row) => row.id.startsWith('cursor-mp-')),
      isFalse,
    );
    final persisted = await repo.load();
    expect(
      persisted.first.endpointConfig.credentialSource,
      'cli:cursor-account',
    );
    await cubit.close();
    await appCubit.close();
  });

  test('delete removes the dedicated CLI row and its directory', () async {
    final appCubit = _appCubit();
    final janitor = ManagedProviderCliRowJanitor(
      fs: fs,
      basePath: '/tp',
      appProviderCubit: appCubit,
    );
    final cubit = ManagedProviderCubit(
      repository: repo,
      appProviderCubit: appCubit,
      rowJanitor: janitor,
    );
    await cubit.upsert(_entry(id: 'managed-4'));
    await fs.ensureDir('/tp/providers/cursor/cursor-mp-managed-4/home');

    await cubit.delete('managed-4');

    expect(cubit.state.providerFor('managed-4'), isNull);
    expect(
      appCubit.state
          .providersFor(CliTool.cursor)
          .any((row) => row.id == 'cursor-mp-managed-4'),
      isFalse,
    );
    expect(
      (await fs.stat('/tp/providers/cursor/cursor-mp-managed-4')).exists,
      isFalse,
    );
    await cubit.close();
    await appCubit.close();
  });

  test('delete of a non-cli entry has no CLI side effects', () async {
    final appCubit = _appCubit();
    await appCubit.upsertProvider(AppProviderConfig(
      id: 'cursor-keep',
      cli: CliTool.cursor,
      name: 'Keep',
    ));
    final janitor = ManagedProviderCliRowJanitor(
      fs: fs,
      basePath: '/tp',
      appProviderCubit: appCubit,
    );
    final cubit = ManagedProviderCubit(
      repository: repo,
      appProviderCubit: appCubit,
      rowJanitor: janitor,
    );
    await repo.save([
      ManagedProvider(
        id: 'managed-5',
        name: 'API balance',
        kind: ManagedProviderKind.apiBalance,
        adapterId: 'http-json',
        endpointConfig: ManagedProviderEndpointConfig(
          url: 'https://example.test/usage',
          credentialSource: 'secret',
        ),
      ),
    ]);

    await cubit.delete('managed-5');

    expect(
      appCubit.state
          .providersFor(CliTool.cursor)
          .any((row) => row.id == 'cursor-keep'),
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
