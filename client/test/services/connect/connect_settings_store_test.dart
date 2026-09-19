@TestOn('vm')
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ssh_reachability.dart';
import 'package:teampilot/services/connect/connect_ssh_backend.dart';
import 'package:teampilot/services/connect/connect_settings_store.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  late InMemoryFilesystem fs;
  const appDataRoot = '/data';
  const hostId = 'ABCDEFGHijkl1234';

  setUp(() {
    fs = InMemoryFilesystem();
  });

  ConnectSettingsStore newStore() =>
      ConnectSettingsStore(fs: fs, appDataRoot: appDataRoot);

  Future<Map<String, Object?>> readSettings(String path) async {
    final contents = await fs.readString(path);
    expect(contents, isNotNull);
    return jsonDecode(contents!) as Map<String, Object?>;
  }

  test('embeddedPort is picked once and persisted', () async {
    final store = newStore();
    final first = await store.loadOrCreateEmbeddedPort();
    expect(first, inInclusiveRange(49152, 65535));

    final second = await ConnectSettingsStore(
      fs: fs,
      appDataRoot: appDataRoot,
    ).loadOrCreateEmbeddedPort();
    expect(second, first);
  });

  test('embeddedPort out of range is re-picked', () async {
    final store = newStore();
    await fs.ensureDir(fs.pathContext.dirname(store.settingsPath));
    await fs.atomicWrite(
      store.settingsPath,
      '{"hostId":"$hostId","embeddedPort":22}',
    );
    final port = await store.loadOrCreateEmbeddedPort();
    expect(port, inInclusiveRange(49152, 65535));
    expect(port, isNot(22));
  });

  test('repickEmbeddedPort persists a different port', () async {
    final store = newStore();
    final first = await store.loadOrCreateEmbeddedPort();
    var next = first;
    var guard = 0;
    while (next == first && guard++ < 64) {
      next = await store.repickEmbeddedPort();
    }
    expect(next, isNot(first));
  });

  test('save preserves embeddedPort', () async {
    final store = newStore();
    final port = await store.loadOrCreateEmbeddedPort();

    await store.save(
      extraEndpoints: const [
        SshReachabilityEndpoint(
          kind: SshEndpointKind.extra,
          host: 'lan',
          port: 22,
        ),
      ],
      relayUrl: 'https://relay.example',
    );

    final json = await readSettings(store.settingsPath);
    expect(json['embeddedPort'], port);

    final reloaded = await newStore().loadOrCreateEmbeddedPort();
    expect(reloaded, port);
  });

  test('loadOrCreateEmbeddedPort preserves other settings keys', () async {
    final store = newStore();
    await fs.ensureDir(fs.pathContext.dirname(store.settingsPath));
    await fs.atomicWrite(
      store.settingsPath,
      jsonEncode({
        'hostId': hostId,
        'extraEndpoints': [
          {'kind': 'extra', 'host': 'lan', 'port': 2222},
        ],
        'relayUrl': 'https://relay.example',
      }),
    );

    final port = await store.loadOrCreateEmbeddedPort();
    final json = await readSettings(store.settingsPath);
    expect(json['hostId'], hostId);
    expect(json['embeddedPort'], port);
    expect((json['extraEndpoints'] as List).first['host'], 'lan');
    expect(json['relayUrl'], 'https://relay.example');
  });

  test('load defaults sshBackend to embedded', () async {
    final settings = await newStore().load();
    expect(settings.sshBackend, ConnectSshBackendKind.embedded);
  });

  test(
    'saveSshBackend round-trips system and preserves embeddedPort',
    () async {
      final store = newStore();
      final port = await store.loadOrCreateEmbeddedPort();
      await store.saveSshBackend(ConnectSshBackendKind.system);
      final json = await readSettings(store.settingsPath);
      expect(json['sshBackend'], 'system');
      expect(json['embeddedPort'], port);
      expect(
        (await newStore().load()).sshBackend,
        ConnectSshBackendKind.system,
      );
    },
  );

  test('reachability save preserves sshBackend', () async {
    final store = newStore();
    await store.saveSshBackend(ConnectSshBackendKind.system);
    await store.save(extraEndpoints: const [], relayUrl: '');
    expect((await newStore().load()).sshBackend, ConnectSshBackendKind.system);
  });
}
