import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/app_provider_cubit.dart';
import 'package:teampilot/cubits/managed_provider_cubit.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/models/managed_provider.dart';
import 'package:teampilot/repositories/app_provider_repository.dart';
import 'package:teampilot/repositories/managed_provider_repository.dart';

import '../support/in_memory_filesystem.dart';

void main() {
  late InMemoryFilesystem fs;
  final usageRepoStub = _UsageRepoStub();
  late ManagedProviderRepository repo;

  setUp(() {
    fs = InMemoryFilesystem();
    usageRepoStub.reset();
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

  test(
    'load migration does not delete a provider upserted during load',
    () async {
      await repo.save([entry(id: 'managed-legacy')]);
      final appCubit = _GatedAppProviderCubit(
        repository: AppProviderRepository(fs: fs, basePath: '/tp'),
      );
      final cubit = ManagedProviderCubit(
        repository: repo,
        appProviderCubit: appCubit,
      );

      // Start the load; it parks inside the migration's CLI-row ensure so the
      // upsert below lands between the load's catalog read and its save.
      final loadFuture = cubit.load();
      await Future<void>.delayed(Duration.zero);
      await cubit.upsert(entry(id: 'managed-new', source: 'secret'));
      appCubit.releaseRowEnsure();
      await loadFuture;

      expect(cubit.state.providerFor('managed-legacy'), isNotNull);
      expect(cubit.state.providerFor('managed-new'), isNotNull);
      final persisted = await repo.load();
      expect(
        persisted.map((provider) => provider.id),
        containsAll(['managed-legacy', 'managed-new']),
      );
      // The deletion barrier must never classify the concurrent upsert as
      // removed just because the migration save had a stale catalog view.
      expect(usageRepoStub.deletedIds, isEmpty);
      await cubit.close();
      await appCubit.close();
    },
  );
}

/// Minimal stub matching ManagedProviderUsageRepository.deleteMany.
class _UsageRepoStub {
  final deletedIds = <String>[];

  void reset() => deletedIds.clear();

  Future<void> deleteMany(List<String> ids) async {
    deletedIds.addAll(ids);
  }
}

/// [AppProviderCubit] whose first CLI-row upsert blocks until released, so a
/// test can deterministically interleave a managed-provider mutation with the
/// load migration path.
class _GatedAppProviderCubit extends AppProviderCubit {
  _GatedAppProviderCubit({required super.repository})
    : _rowEnsureGate = Completer<void>();

  final Completer<void> _rowEnsureGate;

  void releaseRowEnsure() {
    if (!_rowEnsureGate.isCompleted) _rowEnsureGate.complete();
  }

  @override
  Future<bool> upsertProvider(AppProviderConfig provider) async {
    await _rowEnsureGate.future;
    return super.upsertProvider(provider);
  }
}
