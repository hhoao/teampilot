import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/ssh_server_config_cubit.dart';
import 'package:teampilot/models/connection/catalog_entry.dart';
import 'package:teampilot/models/connection/machine_id.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/repositories/catalog_store.dart';
import 'package:teampilot/repositories/connection_store.dart';
import 'package:teampilot/repositories/plane_ssh_profile_repository.dart';

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

  test('separates listed-but-unconnected machines from reachable ones', () async {
    await repo.save(
      const SshProfile(id: 'reachable', name: 'dev', host: 'h', username: 'u'),
    );
    // A plane membership with no device connection.
    await catalog.saveAll(const [
      CatalogEntry(machineId: MachineId('reachable'), displayName: 'dev'),
      CatalogEntry(machineId: MachineId('ghost'), displayName: 'lab-box'),
    ]);
    final cubit = SshServerConfigCubit(repository: repo);
    addTearDown(cubit.close);

    await cubit.load();

    expect(cubit.state.profiles.map((p) => p.id), ['reachable']);
    expect(
      cubit.state.needsConnection.map((e) => e.displayName),
      ['lab-box'],
    );
  });

  test('loads the machines the plane lists and this device can reach', () async {
    final cubit = SshServerConfigCubit(repository: repo);
    addTearDown(cubit.close);

    await cubit.load();

    expect(cubit.state.profiles, isEmpty);
  });

  test('a saved row joins the plane list with a device connection', () async {
    const profile = SshProfile(
      id: 's1',
      name: 'dev',
      host: 'dev.example.com',
      username: 'alice',
    );

    await repo.save(profile);
    final cubit = SshServerConfigCubit(repository: repo);
    addTearDown(cubit.close);
    await cubit.load();

    expect(cubit.state.profiles.single.id, 's1');
    expect(cubit.state.profiles.single.host, 'dev.example.com');
    expect(cubit.state.isLoading, isFalse);
    expect(cubit.state.error, isNull);
    expect((await repo.findById('s1'))?.name, 'dev');
  });

  test('delete removes plane membership but keeps the dial plan', () async {
    const dev = SshProfile(
      id: 's1',
      name: 'dev',
      host: 'dev.example.com',
      username: 'alice',
    );
    const prod = SshProfile(
      id: 's2',
      name: 'prod',
      host: 'prod.example.com',
      username: 'bob',
    );
    await repo.save(dev);
    await repo.save(prod);
    final cubit = SshServerConfigCubit(repository: repo);
    addTearDown(cubit.close);

    await cubit.delete('s1');

    expect(cubit.state.profiles.map((p) => p.id), ['s2']);
    expect(await repo.findById('s1'), isNull);
    // The machine is no longer listed here, but this device still knows how to
    // reach it: the dial plan belongs to the device, not to the plane.
    expect(
      await connections.findById(const MachineId('s1')),
      isNotNull,
    );
  });
}

