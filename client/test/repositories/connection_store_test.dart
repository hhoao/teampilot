import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/connection/machine_id.dart';
import 'package:teampilot/models/ssh_reachability.dart';
import 'package:teampilot/repositories/connection_store.dart';

import '../support/connection_fixtures.dart';
import '../support/in_memory_filesystem.dart';

void main() {
  late InMemoryFilesystem fs;
  late ConnectionStore store;

  setUp(() {
    fs = InMemoryFilesystem();
    store = ConnectionStore(rootDir: '/tp', fs: fs);
  });

  test('saves and loads a connection', () async {
    final connection = deviceConnection(machineId: 't1');
    await store.save(connection);

    expect(await store.loadAll(), [connection]);
    expect((await store.findById(const MachineId('t1')))?.displayName, 'dev');
  });

  test('updates an existing connection by machine id', () async {
    await store.save(deviceConnection(machineId: 't1', displayName: 'a'));
    await store.save(deviceConnection(machineId: 't1', displayName: 'b'));

    final loaded = await store.loadAll();
    expect(loaded, hasLength(1));
    expect(loaded.single.displayName, 'b');
  });

  test('deletes by machine id', () async {
    await store.save(deviceConnection(machineId: 't1'));
    await store.delete(const MachineId('t1'));
    expect(await store.loadAll(), isEmpty);
  });

  test('returns empty when the file is missing', () async {
    expect(await store.loadAll(), isEmpty);
  });

  test('writes schema v2', () async {
    await store.save(deviceConnection());
    final json = jsonDecode((await fs.readString('/tp/remote-targets.json'))!);
    expect(json['schemaVersion'], ConnectionStore.schemaVersion);
    expect(json['connections'], hasLength(1));
  });

  test('refuses a v1 catalog instead of guessing an address set', () async {
    await fs.writeString(
      '/tp/remote-targets.json',
      jsonEncode([
        {'id': 't1', 'name': 'legacy', 'host': 'h', 'username': 'u'},
      ]),
    );

    await expectLater(
      store.loadAll(),
      throwsA(isA<StaleConnectionCatalog>()),
    );
    // The v1 bytes stay untouched for ConnectionBootstrap to upgrade.
    expect(
      (await fs.readString('/tp/remote-targets.json'))!.startsWith('['),
      isTrue,
    );
  });

  test('preserves an unparseable catalog instead of overwriting it', () async {
    const original = '{"schemaVersion":2,"connections":[{';
    await fs.writeString('/tp/remote-targets.json', original);

    await store.save(deviceConnection(machineId: 'new'));

    final loaded = await store.loadAll();
    expect(loaded.map((c) => c.machineId.value), ['new']);
    expect(
      await fs.readString('/tp/remote-targets.corrupt.json'),
      original,
      reason: 'the unreadable file must survive for recovery',
    );
  });

  test('a last-good rewrite keeps the generation stable', () async {
    final first = deviceConnection(
      endpoints: const [
        SshReachabilityEndpoint(kind: SshEndpointKind.lan, host: 'h', port: 22),
        SshReachabilityEndpoint(
          kind: SshEndpointKind.extra,
          host: 'x',
          port: 22,
        ),
      ],
      preferredKind: SshEndpointKind.lan,
    );
    await store.save(first);

    await store.save(first.copyWith(preferredKind: SshEndpointKind.extra));

    final loaded = (await store.loadAll()).single;
    expect(loaded.preferredKind, SshEndpointKind.extra);
    expect(loaded.generation, first.generation);
  });
}
