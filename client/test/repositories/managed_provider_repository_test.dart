import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/managed_provider.dart';
import 'package:teampilot/repositories/managed_provider_repository.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/storage/app_storage.dart';

import '../support/in_memory_filesystem.dart';

ManagedProvider _provider(
  String id, {
  String name = 'Example',
  Map<String, Object?> unknownFields = const {},
}) => ManagedProvider(
  id: id,
  name: name,
  kind: ManagedProviderKind.apiBalance,
  adapterId: 'http-json',
  endpointConfig: ManagedProviderEndpointConfig(url: 'https://example.test'),
  unknownFields: unknownFields,
);

void main() {
  group('ManagedProviderRepository', () {
    late InMemoryFilesystem fs;
    late ManagedProviderRepository repo;
    const path = '/tp/providers/managed/providers.json';

    setUp(() {
      fs = InMemoryFilesystem();
      repo = ManagedProviderRepository(fs: fs, configPath: path);
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
  });
}
