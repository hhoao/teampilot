import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/connection/catalog_entry.dart';
import 'package:teampilot/models/connection/machine_id.dart';
import 'package:teampilot/repositories/catalog_store.dart';
import 'package:teampilot/repositories/connection_store.dart';
import 'package:teampilot/services/connect/catalog_adoption.dart';

import '../support/connection_fixtures.dart';
import '../support/in_memory_filesystem.dart';

void main() {
  late InMemoryFilesystem fs;
  late CatalogStore catalog;
  late ConnectionStore connections;

  setUp(() {
    fs = InMemoryFilesystem();
    final storage = fakeHomeStorage(filesystem: fs);
    catalog = CatalogStore(storage: storage);
    connections = ConnectionStore(rootDir: '/device', fs: fs);
  });

  test('round-trips membership and display names only', () async {
    await catalog.saveAll(const [
      CatalogEntry(
        machineId: MachineId('m1'),
        displayName: 'dev',
        updatedAt: 1,
      ),
    ]);

    final snapshot = await catalog.readSnapshot();
    expect(snapshot?.legacy, isFalse);
    expect(snapshot?.entries.single.displayName, 'dev');
    final json = jsonDecode((await fs.readString(catalog.path))!);
    expect(json['schemaVersion'], CatalogStore.schemaVersion);
    expect(jsonEncode(json), isNot(contains('"host"')));
    expect(jsonEncode(json), isNot(contains('"port"')));
  });

  test('a schema-1 file is read as legacy rows, never as entries', () async {
    await fs.atomicWrite(
      catalog.path,
      jsonEncode([
        {
          'id': 'm1',
          'name': 'dev',
          'host': 'h',
          'port': 22,
          'username': 'u',
          'updatedAt': 1,
        },
      ]),
    );

    final snapshot = await catalog.readSnapshot();

    expect(snapshot?.legacy, isTrue);
    expect(snapshot?.entries.single.displayName, 'dev');
    expect(snapshot?.legacyRows.single.host, 'h');
  });

  test('adoption seeds a connection per legacy row and rewrites v2', () async {
    await fs.atomicWrite(
      catalog.path,
      jsonEncode([
        {
          'id': 'm1',
          'name': 'dev',
          'host': '10.0.0.5',
          'port': 2222,
          'username': 'alice',
          'lastGoodKind': 'lan',
          'updatedAt': 1,
        },
      ]),
    );

    final adopted = await adoptCatalog(
      catalog: catalog,
      connections: connections,
    );

    expect(adopted.seeded, 1);
    expect(adopted.entries.single.machineId.value, 'm1');
    final seeded = (await connections.loadAll()).single;
    expect(seeded.machineId.value, 'm1');
    expect(seeded.primaryEndpoint.host, '10.0.0.5');
    expect(seeded.primaryEndpoint.port, 2222);
    expect(seeded.plan.username, 'alice');
    // The plane no longer carries the address.
    expect(await fs.readString(catalog.path), isNot(contains('10.0.0.5')));
    expect((await catalog.readSnapshot())?.legacy, isFalse);
  });

  test('adoption is idempotent and never overwrites a device connection', () async {
    await fs.atomicWrite(
      catalog.path,
      jsonEncode([
        {
          'id': 'm1',
          'name': 'plane name',
          'host': 'plane-host',
          'port': 22,
          'username': 'u',
        },
      ]),
    );
    await connections.save(deviceConnection(machineId: 'm1'));

    await adoptCatalog(catalog: catalog, connections: connections);

    final connection = (await connections.loadAll()).single;
    expect(connection.primaryEndpoint.host, 'h');
    expect((await connections.loadAll()), hasLength(1));
  });

  test('write helpers refuse a legacy file instead of dropping its rows', () async {
    await fs.atomicWrite(
      catalog.path,
      jsonEncode([
        {
          'id': 'm1',
          'name': 'dev',
          'host': 'h',
          'port': 22,
          'username': 'u',
        },
      ]),
    );

    await catalog.saveEntry(
      const CatalogEntry(machineId: MachineId('m2'), displayName: 'new'),
    );

    expect((await catalog.readSnapshot())?.legacy, isTrue);
    expect((await catalog.readSnapshot())?.entries.single.machineId.value, 'm1');
  });

  test('delete removes one membership after adoption', () async {
    await adoptCatalog(catalog: catalog, connections: connections);
    await catalog.saveAll(const [
      CatalogEntry(machineId: MachineId('m1'), displayName: 'a'),
      CatalogEntry(machineId: MachineId('m2'), displayName: 'b'),
    ]);

    await catalog.delete(const MachineId('m1'));

    expect(
      (await catalog.readSnapshot())?.entries.map((e) => e.machineId.value),
      ['m2'],
    );
  });
}
