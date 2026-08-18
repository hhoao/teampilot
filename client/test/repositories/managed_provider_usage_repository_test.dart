import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/provider_usage_snapshot.dart';
import 'package:teampilot/repositories/managed_provider_usage_repository.dart';
import 'package:teampilot/services/io/filesystem.dart';

import '../support/in_memory_filesystem.dart';

ProviderUsageSnapshot _snapshot(
  String providerId, {
  ProviderUsageStatus status = ProviderUsageStatus.ready,
  int? fetchedAt,
  int? staleAt,
  int schemaVersion = 1,
  Map<String, Object?> unknownFields = const {},
}) => ProviderUsageSnapshot(
  providerId: providerId,
  status: status,
  measures: [
    ProviderUsageMeasure(
      label: 'Balance',
      kind: ProviderUsageMeasureKind.balance,
      remaining: '12.50',
      unit: 'USD',
    ),
  ],
  fetchedAt: fetchedAt,
  staleAt: staleAt,
  schemaVersion: schemaVersion,
  unknownFields: unknownFields,
);

void main() {
  group('ManagedProviderUsageRepository', () {
    late InMemoryFilesystem fs;
    late ManagedProviderUsageRepository repo;
    const path = '/tp/providers/managed/usage-cache.json';

    setUp(() {
      fs = InMemoryFilesystem();
      repo = ManagedProviderUsageRepository(fs: fs, cachePath: path);
    });

    test('load returns an empty list when the cache file is missing', () async {
      expect(await repo.load(), isEmpty);
    });

    test(
      'save creates the parent directory and round-trips a snapshot',
      () async {
        final snapshot = _snapshot('p1', fetchedAt: 100);

        await repo.save(snapshot);

        expect(
          await fs.stat('/tp/providers/managed'),
          isA<FsStat>().having((stat) => stat.isDirectory, 'isDirectory', true),
        );
        expect(await fs.readString(path), contains('"p1"'));
        expect((await repo.load()).single, snapshot);
      },
    );

    test('malformed top-level JSON does not make the cache throw', () async {
      await fs.writeString(path, '[]');

      expect(await repo.load(), isEmpty);
    });

    test('malformed snapshots are isolated from valid snapshots', () async {
      await fs.writeString(
        path,
        jsonEncode({
          'schemaVersion': 1,
          'snapshots': {
            'valid': _snapshot('valid').toJson(),
            'broken': {'providerId': 42, 'status': 'ready'},
          },
        }),
      );

      final snapshots = await repo.load();

      expect(snapshots.single.providerId, 'valid');
    });

    test('expired cache is returned as stale instead of discarded', () async {
      final repo = ManagedProviderUsageRepository(
        fs: fs,
        cachePath: path,
        now: () => 300,
      );
      await repo.save(_snapshot('p1', fetchedAt: 100, staleAt: 200));

      final result = await repo.load();

      expect(result.single.status, ProviderUsageStatus.stale);
      expect(result.single.fetchedAt, 100);
      expect(result.single.staleAt, 200);
      expect(result.single.measures.single.remaining, '12.50');
    });

    test('save preserves unknown top-level and snapshot fields', () async {
      await fs.writeString(
        path,
        jsonEncode({
          'schemaVersion': 1,
          'futureCacheFlag': 'keep',
          'snapshots': {
            'p1': {
              ..._snapshot('p1').toJson(),
              'futureSnapshotField': ['keep'],
            },
          },
        }),
      );

      await repo.save(_snapshot('p1', status: ProviderUsageStatus.stale));

      final raw = await fs.readString(path);
      final decoded = jsonDecode(raw!) as Map;
      expect(decoded['futureCacheFlag'], 'keep');
      expect((decoded['snapshots'] as Map)['p1']['futureSnapshotField'], [
        'keep',
      ]);
    });

    test('save preserves unknown fields on individual measures', () async {
      final original = _snapshot('p1').toJson();
      original['measures'] = [
        {
          ...(original['measures'] as List).single as Map,
          'futureMeasureField': {'keep': true},
        },
      ];
      await fs.writeString(
        path,
        jsonEncode({
          'schemaVersion': 9,
          'snapshots': {'p1': original},
        }),
      );

      await repo.save(_snapshot('p1', status: ProviderUsageStatus.stale));

      final raw = await fs.readString(path);
      final snapshot = (jsonDecode(raw!) as Map)['snapshots']['p1'] as Map;
      expect((snapshot['measures'] as List).single['futureMeasureField'], {
        'keep': true,
      });
    });

    test('updating a valid snapshot preserves malformed raw entries', () async {
      await fs.writeString(
        path,
        jsonEncode({
          'schemaVersion': 1,
          'snapshots': {
            'valid': _snapshot('valid').toJson(),
            'broken': {'providerId': 42, 'status': 'ready'},
            'future-record': 'preserve me',
          },
        }),
      );

      await repo.save(_snapshot('valid', status: ProviderUsageStatus.stale));

      final snapshots =
          (jsonDecode(await fs.readString(path) ?? '') as Map)['snapshots']
              as Map;
      expect(snapshots['broken'], {'providerId': 42, 'status': 'ready'});
      expect(snapshots['future-record'], 'preserve me');
      expect((await repo.load()).single.status, ProviderUsageStatus.stale);
    });

    test('sanitizes secrets in preserved malformed snapshot records', () async {
      await fs.writeString(
        path,
        jsonEncode({
          'schemaVersion': 1,
          'snapshots': {
            'valid': _snapshot('valid').toJson(),
            ' p1 ': {
              'providerId': 42,
              'status': 'ready',
              'apiKey': 'api-secret',
              'token': 'token-secret',
              'X-Api-Key': 'x-api-secret',
              'bearerValue': 'Bearer bearer-secret',
              'nested': {'token': 'nested-token-secret', 'safe': 'keep'},
            },
          },
        }),
      );

      await repo.save(_snapshot('valid', status: ProviderUsageStatus.stale));

      final snapshots =
          (jsonDecode(await fs.readString(path) ?? '') as Map)['snapshots']
              as Map;
      final rawSnapshot = snapshots['p1'] as Map;
      expect(jsonEncode(rawSnapshot), isNot(contains('secret')));
      expect((rawSnapshot['nested'] as Map)['safe'], 'keep');
      expect(rawSnapshot.containsKey('apiKey'), isFalse);
      expect(rawSnapshot.containsKey('token'), isFalse);
      expect(rawSnapshot.containsKey('X-Api-Key'), isFalse);
    });

    test(
      'drops blank raw IDs and resolves raw IDs colliding with parsed IDs',
      () async {
        await fs.writeString(
          path,
          jsonEncode({
            'schemaVersion': 1,
            'snapshots': {
              'p1': _snapshot('p1').toJson(),
              ' p1 ': {'providerId': 42, 'status': 'ready'},
              '  ': {'token': 'blank-secret'},
            },
          }),
        );

        await repo.save(_snapshot('p1', status: ProviderUsageStatus.stale));

        final snapshots =
            (jsonDecode(await fs.readString(path) ?? '') as Map)['snapshots']
                as Map;
        expect(snapshots.keys, ['p1']);
        expect((await repo.load()).single.status, ProviderUsageStatus.stale);
      },
    );

    test(
      'delete removes a malformed snapshot by normalized provider ID',
      () async {
        await fs.writeString(
          path,
          jsonEncode({
            'schemaVersion': 1,
            'snapshots': {
              ' p1 ': {'providerId': 42, 'status': 'ready'},
              'p2': _snapshot('p2').toJson(),
            },
          }),
        );

        await repo.delete('p1');

        final snapshots =
            (jsonDecode(await fs.readString(path) ?? '') as Map)['snapshots']
                as Map;
        expect(snapshots.containsKey(' p1 '), isFalse);
        expect((await repo.load()).single.providerId, 'p2');
      },
    );

    test('preserves the existing top-level schema version on update', () async {
      await fs.writeString(
        path,
        jsonEncode({'schemaVersion': 9, 'snapshots': {}}),
      );

      await repo.save(_snapshot('p1'));

      final raw = await fs.readString(path);
      expect((jsonDecode(raw!) as Map)['schemaVersion'], 9);
    });

    test(
      'preserves the newer snapshot entity schema version on merge',
      () async {
        await repo.save(_snapshot('p1', schemaVersion: 4));

        await repo.save(
          _snapshot('p1', status: ProviderUsageStatus.stale, schemaVersion: 2),
        );
        var loaded = (await repo.load()).single;
        expect(loaded.schemaVersion, 4);

        await repo.save(_snapshot('p1', schemaVersion: 5));
        loaded = (await repo.load()).single;
        expect(loaded.schemaVersion, 5);
      },
    );

    test('normalizes snapshot IDs and never writes empty IDs', () async {
      await repo.save(_snapshot(' p1 '));
      await repo.save(_snapshot('p1'));
      await repo.save(_snapshot('  '));

      expect((await repo.load()).map((snapshot) => snapshot.providerId), [
        'p1',
      ]);
      final raw = await fs.readString(path);
      expect((jsonDecode(raw!) as Map)['snapshots'].keys, ['p1']);

      await repo.delete(' p1 ');
      expect(await repo.load(), isEmpty);
    });

    test(
      'concurrent saves from separate instances do not lose updates',
      () async {
        final first = ManagedProviderUsageRepository(fs: fs, cachePath: path);
        final second = ManagedProviderUsageRepository(fs: fs, cachePath: path);

        await Future.wait([
          first.save(_snapshot('p1')),
          second.save(_snapshot('p2')),
        ]);

        expect(
          (await repo.load()).map((snapshot) => snapshot.providerId).toSet(),
          {'p1', 'p2'},
        );
      },
    );

    test(
      'delete removes one provider snapshot and clear removes the rest',
      () async {
        await repo.save(_snapshot('p1'));
        await repo.save(_snapshot('p2'));

        await repo.delete('p1');
        expect((await repo.load()).map((snapshot) => snapshot.providerId), [
          'p2',
        ]);

        await repo.clear();
        expect(await repo.load(), isEmpty);
      },
    );

    test(
      'deleteMany removes all normalized provider IDs in one boundary',
      () async {
        await repo.save(_snapshot('p1'));
        await repo.save(_snapshot('p2'));

        await repo.deleteMany([' p1 ', 'p2']);

        expect(await repo.load(), isEmpty);
      },
    );
  });
}
