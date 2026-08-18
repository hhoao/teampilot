import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:teampilot/cubits/managed_provider_cubit.dart';
import 'package:teampilot/models/managed_provider.dart';
import 'package:teampilot/repositories/managed_provider_repository.dart';
import 'package:teampilot/repositories/managed_provider_usage_repository.dart';

import '../support/in_memory_filesystem.dart';

ManagedProvider _provider({
  String id = 'p1',
  String name = 'Provider 1',
  bool enabled = true,
}) => ManagedProvider(
  id: id,
  name: name,
  kind: ManagedProviderKind.apiBalance,
  adapterId: 'fake',
  enabled: enabled,
);

class _BlockingConfigReadFilesystem extends InMemoryFilesystem {
  final blocked = Completer<void>();
  bool blockNextConfigRead = false;
  bool failBlockedRead = false;

  @override
  Future<String?> readString(String path) async {
    if (blockNextConfigRead && path == '/tp/providers.json') {
      blockNextConfigRead = false;
      await blocked.future;
      if (failBlockedRead) throw StateError('stale read failure');
    }
    return super.readString(path);
  }
}

void main() {
  late InMemoryFilesystem fs;
  late ManagedProviderUsageRepository usageRepository;
  late ManagedProviderRepository repository;

  setUp(() {
    fs = InMemoryFilesystem();
    usageRepository = ManagedProviderUsageRepository(
      fs: fs,
      cachePath: '/tp/usage-cache.json',
    );
    repository = ManagedProviderRepository(
      fs: fs,
      configPath: '/tp/providers.json',
      onProvidersDeleted: usageRepository.deleteMany,
    );
  });

  test('hydrates providers and exposes stable selectors', () async {
    await repository.upsert(_provider());
    final cubit = ManagedProviderCubit(repository: repository);
    addTearDown(cubit.close);

    await cubit.load();

    expect(cubit.state.status, ManagedProviderLoadStatus.ready);
    expect(cubit.state.providerFor('p1')?.name, 'Provider 1');
    expect(cubit.state.enabledProviders.map((p) => p.id), ['p1']);
  });

  test(
    'upsert, enable/disable, and delete persist through the repository',
    () async {
      final cubit = ManagedProviderCubit(repository: repository);
      addTearDown(cubit.close);
      await cubit.load();

      await cubit.add(_provider());
      await cubit.update(_provider(name: 'Renamed'));
      await cubit.disable('p1');
      expect(cubit.state.providerFor('p1')!.enabled, isFalse);
      await cubit.enable('p1');
      expect(cubit.state.providerFor('p1')!.enabled, isTrue);

      await cubit.delete('p1');
      expect(cubit.state.providerFor('p1'), isNull);
      expect((await repository.load()), isEmpty);
    },
  );

  test(
    'deletion callback runs before the in-memory provider disappears',
    () async {
      final events = <String>[];
      final repo = ManagedProviderRepository(
        fs: fs,
        configPath: '/tp/providers.json',
        onProvidersDeleted: (ids) async => events.add('cleanup:${ids.single}'),
      );
      await repo.upsert(_provider());
      final cubit = ManagedProviderCubit(
        repository: repo,
        onProviderDeletedState: (id) async => events.add('memory:$id'),
      );
      addTearDown(cubit.close);
      await cubit.load();

      await cubit.delete('p1');

      expect(events, ['cleanup:p1', 'memory:p1']);
      expect(cubit.state.providers, isEmpty);
    },
  );

  test('a load started before upsert cannot overwrite the mutation', () async {
    final blockingFs = _BlockingConfigReadFilesystem();
    final blockingRepository = ManagedProviderRepository(
      fs: blockingFs,
      configPath: '/tp/providers.json',
      onProvidersDeleted: (_) async {},
    );
    await blockingRepository.upsert(_provider(name: 'old'));
    final cubit = ManagedProviderCubit(repository: blockingRepository);
    addTearDown(cubit.close);
    blockingFs.blockNextConfigRead = true;

    final load = cubit.load();
    await Future<void>.delayed(Duration.zero);
    final upsert = cubit.upsert(_provider(name: 'new'));
    await upsert;
    blockingFs.blocked.complete();
    await load;

    expect(cubit.state.providerFor('p1')!.name, 'new');
  });

  test('a stale load failure cannot overwrite a successful mutation', () async {
    final blockingFs = _BlockingConfigReadFilesystem();
    final blockingRepository = ManagedProviderRepository(
      fs: blockingFs,
      configPath: '/tp/providers.json',
      onProvidersDeleted: (_) async {},
    );
    await blockingRepository.upsert(_provider(name: 'old'));
    final cubit = ManagedProviderCubit(repository: blockingRepository);
    addTearDown(cubit.close);
    blockingFs
      ..blockNextConfigRead = true
      ..failBlockedRead = true;

    final load = cubit.load();
    await Future<void>.delayed(Duration.zero);
    final upsert = cubit.upsert(_provider(name: 'new'));
    await upsert;
    blockingFs.blocked.complete();
    await load;

    expect(cubit.state.status, ManagedProviderLoadStatus.ready);
    expect(cubit.state.errorCode, isNull);
    expect(cubit.state.providerFor('p1')!.name, 'new');
  });

  test('a no-op enable does not strand a concurrent load', () async {
    await repository.upsert(_provider(enabled: true));
    final blockingFs = _BlockingConfigReadFilesystem();
    final blockingRepository = ManagedProviderRepository(
      fs: blockingFs,
      configPath: '/tp/providers.json',
      onProvidersDeleted: (_) async {},
    );
    await blockingRepository.upsert(_provider(enabled: true));
    final cubit = ManagedProviderCubit(repository: blockingRepository);
    addTearDown(cubit.close);
    await cubit.load();
    blockingFs.blockNextConfigRead = true;

    final load = cubit.load();
    await Future<void>.delayed(Duration.zero);
    await cubit.enable('p1');
    blockingFs.blocked.complete();
    await load;

    expect(cubit.state.status, ManagedProviderLoadStatus.ready);
    expect(cubit.state.providerFor('p1')!.enabled, isTrue);
  });

  test(
    'enable queued after delete cannot resurrect the deleted provider',
    () async {
      await repository.upsert(_provider(enabled: false));
      final cubit = ManagedProviderCubit(repository: repository);
      addTearDown(cubit.close);
      await cubit.load();

      final delete = cubit.delete('p1');
      final enable = cubit.enable('p1');
      await Future.wait([delete, enable]);

      expect(cubit.state.providerFor('p1'), isNull);
      expect(await repository.load(), isEmpty);
    },
  );

  test('cleanup failures expose a secret-free stable error state', () async {
    final failingRepository = ManagedProviderRepository(
      fs: fs,
      configPath: '/tp/providers.json',
      onProvidersDeleted: (_) async => throw StateError('storage path secret'),
    );
    await failingRepository.upsert(_provider());
    final cubit = ManagedProviderCubit(repository: failingRepository);
    addTearDown(cubit.close);
    await cubit.load();

    await cubit.delete('p1');

    expect(cubit.state.errorCode, ManagedProviderErrorCode.deleteFailed);
    expect(cubit.state.errorMessage, isNot(contains('storage path secret')));
  });

  test('closing during a blocked load does not emit or throw', () async {
    final blockingFs = _BlockingConfigReadFilesystem();
    final blockingRepository = ManagedProviderRepository(
      fs: blockingFs,
      configPath: '/tp/providers.json',
      onProvidersDeleted: (_) async {},
    );
    final cubit = ManagedProviderCubit(repository: blockingRepository);
    blockingFs.blockNextConfigRead = true;
    final load = cubit.load();
    await Future<void>.delayed(Duration.zero);
    await cubit.close();
    blockingFs.blocked.complete();

    await expectLater(load, completes);
  });
}
