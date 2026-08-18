import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/managed_provider.dart';
import 'package:teampilot/models/provider_usage_snapshot.dart';
import 'package:teampilot/repositories/managed_provider_repository.dart';
import 'package:teampilot/repositories/managed_provider_usage_repository.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/storage/app_storage.dart';

import '../support/in_memory_filesystem.dart';

ManagedProvider _provider(
  String id, {
  String name = 'Example',
  int schemaVersion = 1,
  Map<String, Object?> unknownFields = const {},
}) => ManagedProvider(
  id: id,
  name: name,
  kind: ManagedProviderKind.apiBalance,
  adapterId: 'http-json',
  endpointConfig: ManagedProviderEndpointConfig(url: 'https://example.test'),
  schemaVersion: schemaVersion,
  unknownFields: unknownFields,
);

void main() {
  group('ManagedProviderRepository', () {
    late InMemoryFilesystem fs;
    late ManagedProviderRepository repo;
    const path = '/tp/providers/managed/providers.json';

    setUp(() {
      fs = InMemoryFilesystem();
      repo = ManagedProviderRepository(
        fs: fs,
        configPath: path,
        onProviderDeleted: (_) async {},
      );
    });

    test('AppPaths exposes managed provider files below providers/managed', () {
      final paths = AppPaths('/tp');
      expect(paths.managedProviderConfigFile, path);
      expect(
        paths.managedProviderUsageCacheFile,
        '/tp/providers/managed/usage-cache.json',
      );
    });

    test(
      'load returns an empty list when the config file is missing',
      () async {
        expect(await repo.load(), isEmpty);
      },
    );

    test('save creates the parent directory with an atomic write', () async {
      final provider = _provider('p1');

      await repo.save([provider]);

      expect(
        await fs.stat('/tp/providers/managed'),
        isA<FsStat>().having((stat) => stat.isDirectory, 'isDirectory', true),
      );
      expect(await fs.readString(path), contains('"p1"'));
      expect(await repo.load(), [provider]);
    });

    test('malformed top-level JSON does not prevent a later save', () async {
      await fs.writeString(path, '{not valid');

      expect(await repo.load(), isEmpty);
      await repo.save([_provider('p1')]);

      expect((await repo.load()).single.id, 'p1');
    });

    test(
      'malformed provider entries are isolated from valid entries',
      () async {
        final valid = _provider('valid').toJson();
        await fs.writeString(
          path,
          jsonEncode({
            'schemaVersion': 1,
            'providers': {
              'valid': valid,
              'broken': {'name': 42},
            },
          }),
        );

        final providers = await repo.load();

        expect(providers, [_provider('valid')]);
      },
    );

    test('upsert preserves unknown top-level and provider fields', () async {
      await fs.writeString(
        path,
        jsonEncode({
          'schemaVersion': 1,
          'futureCatalogFlag': true,
          'providers': {
            'p1': {
              ..._provider('p1').toJson(),
              'futureProviderField': {'enabled': true},
            },
          },
        }),
      );

      await repo.upsert(_provider('p1', name: 'Renamed'));

      final raw = await fs.readString(path);
      final decoded = jsonDecode(raw!) as Map;
      expect(decoded['futureCatalogFlag'], true);
      expect((decoded['providers'] as Map)['p1']['futureProviderField'], {
        'enabled': true,
      });
      expect((await repo.load()).single.name, 'Renamed');
    });

    test('upsert preserves nested unknown provider fields', () async {
      final original = _provider('p1').toJson();
      original['brand'] = {
        ...(original['brand'] as Map),
        'futureBrandField': 'keep',
      };
      original['endpointConfig'] = {
        ...(original['endpointConfig'] as Map),
        'futureEndpointField': {'keep': true},
      };
      original['displayConfig'] = {
        ...(original['displayConfig'] as Map),
        'futureDisplayField': ['keep'],
      };
      await fs.writeString(
        path,
        jsonEncode({
          'schemaVersion': 7,
          'providers': {'p1': original},
        }),
      );

      await repo.upsert(_provider('p1', name: 'Updated'));

      final raw = await fs.readString(path);
      final provider = (jsonDecode(raw!) as Map)['providers']['p1'] as Map;
      expect((provider['brand'] as Map)['futureBrandField'], 'keep');
      expect((provider['endpointConfig'] as Map)['futureEndpointField'], {
        'keep': true,
      });
      expect((provider['displayConfig'] as Map)['futureDisplayField'], [
        'keep',
      ]);
    });

    test('preserves the existing top-level schema version on update', () async {
      await fs.writeString(
        path,
        jsonEncode({'schemaVersion': 7, 'providers': {}}),
      );

      await repo.upsert(_provider('p1'));

      final raw = await fs.readString(path);
      expect((jsonDecode(raw!) as Map)['schemaVersion'], 7);
    });

    test(
      'preserves the newer provider entity schema version on merge',
      () async {
        await repo.save([_provider('p1', schemaVersion: 4)]);

        await repo.upsert(_provider('p1', name: 'Older', schemaVersion: 2));
        var loaded = (await repo.load()).single;
        expect(loaded.schemaVersion, 4);

        await repo.upsert(_provider('p1', name: 'Newer', schemaVersion: 5));
        loaded = (await repo.load()).single;
        expect(loaded.schemaVersion, 5);
      },
    );

    test('normalizes provider IDs and never writes empty IDs', () async {
      await repo.save([_provider(' p1 '), _provider('p1'), _provider('  ')]);

      expect((await repo.load()).map((provider) => provider.id), ['p1']);
      final raw = await fs.readString(path);
      expect((jsonDecode(raw!) as Map)['providers'].keys, ['p1']);

      await repo.delete(' p1 ');
      expect(await repo.load(), isEmpty);
    });

    test('upsert replaces by id and delete cleans up that provider', () async {
      await repo.save([_provider('p1'), _provider('p2')]);

      await repo.upsert(_provider('p1', name: 'Updated'));
      expect((await repo.load()).map((provider) => provider.name), [
        'Updated',
        'Example',
      ]);

      await repo.delete('p1');

      expect((await repo.load()).map((provider) => provider.id), ['p2']);
    });

    test('deleting a provider invokes the cache cleanup boundary', () async {
      final usageRepo = ManagedProviderUsageRepository(
        fs: fs,
        cachePath: '/tp/providers/managed/usage-cache.json',
      );
      repo = ManagedProviderRepository(
        fs: fs,
        configPath: path,
        onProviderDeleted: usageRepo.delete,
      );
      await repo.save([_provider('p1')]);
      await usageRepo.save(
        ProviderUsageSnapshot(
          providerId: 'p1',
          status: ProviderUsageStatus.ready,
        ),
      );

      await repo.delete(' p1 ');

      expect(await repo.load(), isEmpty);
      expect(await usageRepo.load(), isEmpty);
    });
  });
}
