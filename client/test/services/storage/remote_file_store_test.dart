import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/ssh_known_host_repository.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/ssh/ssh_client_factory.dart';
import 'package:teampilot/services/ssh/ssh_storage_io.dart';
import 'package:teampilot/services/ssh/worker/ssh_worker_storage_client.dart';
import 'package:teampilot/services/ssh/worker/ssh_worker_storage_types.dart';
import 'package:teampilot/services/storage/remote_file_store.dart';

void main() {
  const profile = SshProfile(
    id: 'p1',
    name: 'remote',
    host: 'example.test',
    username: 'tester',
  );

  late SshClientFactory factory;
  late _FakeWorkerStorage storage;
  late RemoteFileStore store;
  late List<Duration> storageForTimeouts;

  setUp(() {
    factory = SshClientFactory(
      credentialStore: InMemorySshCredentialStore(),
      knownHostRepository: InMemorySshKnownHostRepository(),
    );
    storage = _FakeWorkerStorage();
    storageForTimeouts = [];
    store = RemoteFileStore(
      profile: profile,
      clientFactory: factory,
      storageFor: ({timeout = SshStorageIo.ioTimeout}) async {
        storageForTimeouts.add(timeout);
        return storage;
      },
    );
  });

  tearDown(() => factory.disconnectAll());

  test('maps worker stat DTOs and missing files to FsStat', () async {
    storage.stats['/dir'] = const SshWorkerFileStat(
      size: 12,
      modifyTime: 42,
      kind: 'directory',
    );

    final stat = await store.stat('/dir');
    final missing = await store.stat('/missing');

    expect(stat.kind, FsEntityKind.directory);
    expect(stat.size, 12);
    expect(stat.mtime, DateTime.fromMillisecondsSinceEpoch(42000));
    expect(missing.kind, FsEntityKind.notFound);
  });

  test(
    'tracked worker operations use the bounded storage I/O timeout',
    () async {
      await store.stat('/missing');

      expect(storageForTimeouts, [SshStorageIo.ioTimeout]);
    },
  );

  test('uses worker chunks for full and ranged binary reads', () async {
    storage.files['/payload.bin'] = Uint8List.fromList([0, 1, 2, 3, 4]);

    expect(await store.readFileBytes('/payload.bin'), [0, 1, 2, 3, 4]);
    expect(
      await store.readFileBytesRange('/payload.bin', offset: 2, length: 2),
      [2, 3],
    );
    expect(storage.reads, [
      (path: '/payload.bin', offset: 0, length: null),
      (path: '/payload.bin', offset: 2, length: 2),
    ]);
  });

  test('writes and appends through acknowledged worker chunks', () async {
    await store.writeBytes('/payload.bin', Uint8List.fromList([1, 2]));
    await store.appendBytes('/payload.bin', Uint8List.fromList([3]));

    expect(storage.files['/payload.bin'], [1, 2, 3]);
    expect(storage.writes, [
      (path: '/payload.bin', append: false),
      (path: '/payload.bin', append: true),
    ]);
  });
}

final class _FakeWorkerStorage implements SshWorkerStorageFacade {
  final stats = <String, SshWorkerFileStat>{};
  final files = <String, Uint8List>{};
  final reads = <({String path, int offset, int? length})>[];
  final writes = <({String path, bool append})>[];

  @override
  Future<SshWorkerFileStat> stat(
    String path, {
    Duration timeout = SshStorageIo.ioTimeout,
  }) async {
    final value = stats[path];
    if (value == null) throw _missing();
    return value;
  }

  @override
  Future<Uint8List> readBytes(
    String path, {
    int offset = 0,
    int? length,
    Duration timeout = SshStorageIo.ioTimeout,
  }) async {
    reads.add((path: path, offset: offset, length: length));
    final bytes = files[path];
    if (bytes == null) throw _missing();
    final end = length == null
        ? bytes.length
        : (offset + length).clamp(offset, bytes.length);
    return Uint8List.fromList(
      bytes.sublist(offset.clamp(0, bytes.length), end),
    );
  }

  @override
  Future<void> writeBytes(
    String path,
    Uint8List bytes, {
    bool append = false,
    Duration timeout = SshStorageIo.ioTimeout,
  }) async {
    writes.add((path: path, append: append));
    files[path] = Uint8List.fromList([if (append) ...?files[path], ...bytes]);
  }

  @override
  Future<List<SshWorkerDirectoryEntry>> listDirectory(
    String path, {
    Duration timeout = SshStorageIo.ioTimeout,
  }) async => const [];

  @override
  Future<void> mkdir(
    String path, {
    Duration timeout = SshStorageIo.ioTimeout,
  }) async {}

  @override
  Future<String> readlink(
    String path, {
    Duration timeout = SshStorageIo.ioTimeout,
  }) async => path;

  @override
  Future<String> realpath(
    String path, {
    Duration timeout = SshStorageIo.ioTimeout,
  }) async => path;

  @override
  Future<void> remove(
    String path, {
    bool directory = false,
    Duration timeout = SshStorageIo.ioTimeout,
  }) async {}

  SshWorkerTransportException _missing() =>
      const SshWorkerTransportException('missing', code: 'sftp_no_such_file');
}
