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
        onProvidersDeleted: (ids) async => events.add('memory:${ids.single}'),
      );
      addTearDown(cubit.close);
      await cubit.load();

      await cubit.delete('p1');

      expect(events, ['cleanup:p1', 'memory:p1']);
      expect(cubit.state.providers, isEmpty);
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
}
