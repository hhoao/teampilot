import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/models/ssh_reachability.dart';
import 'package:teampilot/repositories/connection_store.dart';
import 'package:teampilot/services/connect/connection_bootstrap.dart';
import 'package:teampilot/services/ssh/ssh_transport_close.dart';

import '../../support/connection_fixtures.dart';
import '../../support/in_memory_filesystem.dart';

const _root = '/tp';
const _marker = '$_root/.connection-catalog.v2';
const _legacyProfiles = '$_root/ssh_profiles/profiles.json';

void main() {
  test('migrates legacy profiles into connections once', () async {
    final fs = InMemoryFilesystem();
    await _writeLegacyProfiles(fs, [
      const SshProfile(id: 'p1', name: 'dev', host: 'h', username: 'u'),
    ]);
    final store = ConnectionStore(rootDir: _root, fs: fs);

    final first = await bootstrapConnections(
      nativeAppDataPath: _root,
      localFs: fs,
      connections: store,
    );
    expect(first.fromLegacyProfiles, 1);
    expect(first.skipped, isFalse);
    expect((await store.loadAll()).single.machineId.value, 'p1');
    expect((await fs.stat(_marker)).exists, isTrue);
    // The legacy file is relocated so the home plane never parses it as a
    // reduced-schema server row.
    expect((await fs.stat(_legacyProfiles)).exists, isFalse);
    expect((await fs.stat('$_legacyProfiles.legacy.v1')).isFile, isTrue);

    final second = await bootstrapConnections(
      nativeAppDataPath: _root,
      localFs: fs,
      connections: store,
    );
    expect(second.skipped, isTrue);
    expect(second.fromLegacyProfiles, 0);
  });

  test('upgrades a v1 address row into a plan without losing fields', () async {
    final fs = InMemoryFilesystem();
    await fs.atomicWrite(
      '$_root/remote-targets.json',
      jsonEncode([
        {
          'schemaVersion': 1,
          'id': 'p1',
          'name': 'desk',
          'host': '10.0.0.5',
          'port': 2222,
          'username': 'alice',
          'authType': 'privateKey',
          'vaultEntryId': 'vault-1',
          'hostKeyFingerprints': ['SHA256:abc'],
          'lastGoodKind': 'lan',
          'lastHome': '/home/alice',
          'lastAppDataRoot': '/data/alice',
          'embeddedTarget': true,
          'relayUrl': 'wss://relay',
          'pairedDesktopId': 'desk-1',
          'updatedAt': 7,
        },
      ]),
    );
    final store = ConnectionStore(rootDir: _root, fs: fs);

    final result = await bootstrapConnections(
      nativeAppDataPath: _root,
      localFs: fs,
      connections: store,
    );
    expect(result.upgraded, 1);
    expect(result.skipped, isFalse);

    final connection = (await store.loadAll()).single;
    expect(connection.machineId.value, 'p1');
    expect(connection.displayName, 'desk');
    expect(connection.plan.username, 'alice');
    expect(connection.plan.authType, SshAuthType.privateKey);
    expect(connection.plan.credentialRef, 'vault-1');
    expect(connection.plan.hostKeyFingerprints, ['SHA256:abc']);
    expect(connection.plan.embeddedTarget, isTrue);
    expect(connection.plan.relayUrl, 'wss://relay');
    expect(connection.preferredKind, SshEndpointKind.lan);
    expect(connection.paths?.home, '/home/alice');
    expect(connection.paths?.appDataRoot, '/data/alice');
    expect(connection.pairedDesktopId, 'desk-1');
    // The v1 address becomes the plan's first endpoint.
    expect(connection.primaryEndpoint.host, '10.0.0.5');
    expect(connection.primaryEndpoint.port, 2222);
    // The original rows survive as a recoverable backup.
    expect(
      (await fs.stat('$_root/remote-targets.json.legacy.v1')).isFile,
      isTrue,
    );
  });

  test('keeps the legacy file and retries when it is unreadable', () async {
    final fs = InMemoryFilesystem();
    await fs.atomicWrite(_legacyProfiles, '{not json');
    final store = ConnectionStore(rootDir: _root, fs: fs);

    final failed = await bootstrapConnections(
      nativeAppDataPath: _root,
      localFs: fs,
      connections: store,
    );
    expect(failed.skipped, isFalse);
    expect(await fs.readString(_legacyProfiles), '{not json');
    expect((await fs.stat(_marker)).exists, isFalse);
    expect(await store.loadAll(), isEmpty);

    await _writeLegacyProfiles(fs, [
      const SshProfile(id: 'p1', name: 'dev', host: 'h', username: 'u'),
    ]);
    final retried = await bootstrapConnections(
      nativeAppDataPath: _root,
      localFs: fs,
      connections: store,
    );
    expect(retried.fromLegacyProfiles, 1);
    expect((await fs.stat(_marker)).exists, isTrue);
  });

  test('failed marker write leaves the marker absent and retries', () async {
    final fs = _MarkerFailingFilesystem(_marker);
    await _writeLegacyProfiles(fs, [
      const SshProfile(id: 'p1', name: 'dev', host: 'h', username: 'u'),
    ]);
    final store = ConnectionStore(rootDir: _root, fs: fs);

    await expectLater(
      bootstrapConnections(
        nativeAppDataPath: _root,
        localFs: fs,
        connections: store,
      ),
      throwsA(isA<StateError>()),
    );
    expect((await fs.stat(_marker)).exists, isFalse);
    expect((await fs.stat(_legacyProfiles)).isFile, isTrue);

    final retried = await bootstrapConnections(
      nativeAppDataPath: _root,
      localFs: fs,
      connections: store,
    );
    expect(retried.skipped, isFalse);
    expect((await fs.stat(_marker)).exists, isTrue);
    expect(await store.loadAll(), hasLength(1));
  });

  test('rethrows transport failures instead of reporting nothing', () async {
    final transportErrors = <Exception>[
      const SshTransportClosed(
        reason: SshTransportCloseReason.transportError,
        plane: SshTransportPlane.storage,
      ),
      const FormatException('sftp channel closed'),
    ];
    for (final error in transportErrors) {
      final fs = _ReadFailingFilesystem(error);
      await fs.atomicWrite(_legacyProfiles, '[]');
      await expectLater(
        bootstrapConnections(
          nativeAppDataPath: _root,
          localFs: fs,
          connections: ConnectionStore(rootDir: _root, fs: fs),
        ),
        throwsA(same(error)),
      );
      expect((await fs.stat(_marker)).exists, isFalse);
    }
  });

  test('leaves an already-migrated catalog alone', () async {
    final fs = InMemoryFilesystem();
    final store = ConnectionStore(rootDir: _root, fs: fs);
    await store.save(deviceConnection(machineId: 'm1'));
    await fs.atomicWrite(_marker, '1');

    final result = await bootstrapConnections(
      nativeAppDataPath: _root,
      localFs: fs,
      connections: store,
    );

    expect(result.skipped, isTrue);
    expect((await store.loadAll()).single.machineId.value, 'm1');
  });
}

Future<void> _writeLegacyProfiles(
  InMemoryFilesystem fs,
  List<SshProfile> profiles,
) async {
  await fs.ensureDir(fs.pathContext.dirname(_legacyProfiles));
  await fs.atomicWrite(
    _legacyProfiles,
    jsonEncode(profiles.map((profile) => profile.toJson()).toList()),
  );
}

/// Filesystem whose reads fail the way a closed dartssh2 channel does.
class _ReadFailingFilesystem extends InMemoryFilesystem {
  _ReadFailingFilesystem(this._error);

  final Exception _error;

  @override
  Future<String?> readString(String path) async => throw _error;
}

/// Filesystem whose first [atomicWrite] to the migration marker fails, then
/// succeeds — models a transient marker-write failure at boot.
class _MarkerFailingFilesystem extends InMemoryFilesystem {
  _MarkerFailingFilesystem(this._markerPath);

  final String _markerPath;
  bool _failMarker = true;

  @override
  Future<void> atomicWrite(String path, String content) async {
    if (path == _markerPath && _failMarker) {
      _failMarker = false;
      throw StateError('injected marker write failure');
    }
    return super.atomicWrite(path, content);
  }
}
