import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/connection/catalog_entry.dart';
import 'package:teampilot/models/connection/machine_id.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/repositories/catalog_store.dart';
import 'package:teampilot/repositories/connection_store.dart';
import 'package:teampilot/repositories/plane_ssh_profile_repository.dart';

import '../support/connection_fixtures.dart';
import '../support/in_memory_filesystem.dart';

void main() {
  late InMemoryFilesystem fs;
  late CatalogStore catalog;
  late ConnectionStore connections;
  late PlaneSshProfileRepository repo;

  setUp(() {
    fs = InMemoryFilesystem();
    final storage = fakeHomeStorage(filesystem: fs);
    catalog = CatalogStore(storage: storage);
    connections = ConnectionStore(rootDir: '/device', fs: fs);
    repo = PlaneSshProfileRepository(
      storage: storage,
      connections: connections,
      catalog: catalog,
    );
  });

  test('lists the join of plane membership and device reachability', () async {
    await catalog.saveAll(const [
      CatalogEntry(machineId: MachineId('m1'), displayName: 'plane name'),
      CatalogEntry(machineId: MachineId('ghost'), displayName: 'no plan'),
    ]);
    await connections.save(
      deviceConnection(machineId: 'm1', displayName: 'device name'),
    );
    await connections.save(deviceConnection(machineId: 'local-only'));

    final view = await repo.loadView();

    // Membership comes from the plane; the address only from the connection.
    expect(view.reachable.map((p) => p.id), ['m1']);
    expect(view.reachable.single.name, 'plane name');
    expect(view.reachable.single.host, 'h');
    expect(view.reachable.single.username, 'u');
    // The entry with no local plan stays visible as NeedsConnection.
    expect(view.needsConnection.map((e) => e.machineId.value), ['ghost']);
    expect(await repo.loadAll(), hasLength(1));
  });

  test('save writes membership to the plane and the plan to the device', () async {
    await repo.save(
      const SshProfile(
        id: 'm1',
        name: 'dev',
        host: '10.0.0.5',
        port: 2222,
        username: 'alice',
      ),
    );

    final entry = (await catalog.readSnapshot())!.entries.single;
    expect(entry.machineId.value, 'm1');
    expect(entry.displayName, 'dev');
    final connection = (await connections.loadAll()).single;
    expect(connection.primaryEndpoint.port, 2222);
    expect((await repo.loadAll()).single.host, '10.0.0.5');
    // The plane file must not carry the address.
    expect(await fs.readString(catalog.path), isNot(contains('10.0.0.5')));
  });

  test('renaming a plane row never touches the dial plan', () async {
    await repo.save(
      const SshProfile(id: 'm1', name: 'old', host: 'h', username: 'u'),
    );
    final before = (await connections.loadAll()).single;

    await repo.save(
      const SshProfile(id: 'm1', name: 'new', host: 'h', username: 'u'),
    );

    final after = (await connections.loadAll()).single;
    expect(after.displayName, 'new');
    expect(after.generation, before.generation);
    expect((await repo.loadAll()).single.name, 'new');
  });

  test('delete drops membership but keeps the device plan', () async {
    await repo.save(
      const SshProfile(id: 'm1', name: 'dev', host: 'h', username: 'u'),
    );

    await repo.delete('m1');

    expect(await repo.loadAll(), isEmpty);
    expect(await repo.findById('m1'), isNull);
    expect(await connections.findById(const MachineId('m1')), isNotNull);
  });

  test('a connection without plane membership is not listed', () async {
    await connections.save(deviceConnection(machineId: 'm1'));

    expect(await repo.findById('m1'), isNull);
    expect(await repo.loadAll(), isEmpty);
  });

  test('adopts schema-1 plane rows into connections before listing', () async {
    await fs.atomicWrite(
      catalog.path,
      jsonEncode([
        {
          'id': 'm1',
          'name': 'legacy',
          'host': '10.0.0.9',
          'port': 22,
          'username': 'u',
          'authType': 'password',
          'updatedAt': 1,
        },
      ]),
    );

    final profiles = await repo.loadAll();

    expect(profiles.single.id, 'm1');
    expect(profiles.single.host, '10.0.0.9');
    expect(
      (await connections.findById(
        const MachineId('m1'),
      ))?.primaryEndpoint.host,
      '10.0.0.9',
    );
    expect((await catalog.readSnapshot())?.legacy, isFalse);
  });
}
