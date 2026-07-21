import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/team_bus/artifacts/artifact_exceptions.dart';
import 'package:teampilot/services/team_bus/artifacts/artifact_registry.dart';
import 'package:teampilot/services/team_bus/artifacts/artifact_transfer_service.dart';

import '../../../support/in_memory_filesystem.dart';

/// Delegates every [Filesystem] method to [inner], except [stat] which strips
/// size/mtime — mirrors SFTP/WSL backends that historically returned kind only.
class _StatWithoutSize implements Filesystem {
  _StatWithoutSize(this.inner);

  final Filesystem inner;

  @override
  p.Context get pathContext => inner.pathContext;

  @override
  Future<FsStat> stat(String path) async {
    final s = await inner.stat(path);
    return FsStat(kind: s.kind);
  }

  @override
  Future<void> appendBytes(String path, List<int> bytes) =>
      inner.appendBytes(path, bytes);

  @override
  Future<void> ensureDir(String path) => inner.ensureDir(path);

  @override
  Future<void> removeRecursive(String path) => inner.removeRecursive(path);

  @override
  Future<void> rename(String from, String to) => inner.rename(from, to);

  @override
  Future<String?> readString(String path) => inner.readString(path);

  @override
  Future<List<int>?> readBytes(String path) => inner.readBytes(path);

  @override
  Future<void> writeString(String path, String content) =>
      inner.writeString(path, content);

  @override
  Future<void> writeBytes(String path, List<int> bytes) =>
      inner.writeBytes(path, bytes);

  @override
  Future<List<int>?> readBytesRange(String path, int offset, int length) =>
      inner.readBytesRange(path, offset, length);

  @override
  Future<void> atomicWrite(String path, String content) =>
      inner.atomicWrite(path, content);

  @override
  Future<List<FsDirEntry>> listDir(String path) => inner.listDir(path);

  @override
  Future<bool> createSymlink({
    required String target,
    required String linkPath,
  }) => inner.createSymlink(target: target, linkPath: linkPath);

  @override
  Future<String?> readSymlinkTarget(String linkPath) =>
      inner.readSymlinkTarget(linkPath);

  @override
  Future<String?> resolveSymlink(String path) => inner.resolveSymlink(path);

  @override
  Future<void> copyTree({
    required String source,
    required String destination,
  }) => inner.copyTree(source: source, destination: destination);

  @override
  Future<void> copyFile(String source, String destination) =>
      inner.copyFile(source, destination);

  @override
  Future<List<FsDirEntry>> listDirRecursive(String path) =>
      inner.listDirRecursive(path);

  @override
  Future<String> createTempDir({String? prefix, String? parent}) =>
      inner.createTempDir(prefix: prefix, parent: parent);

  @override
  Future<void> appendString(String path, String content) =>
      inner.appendString(path, content);
}

/// Counts [appendBytes] calls while delegating to [inner].
class _CountingAppends implements Filesystem {
  _CountingAppends(this.inner);

  final Filesystem inner;
  var appendCount = 0;

  @override
  p.Context get pathContext => inner.pathContext;

  @override
  Future<void> appendBytes(String path, List<int> bytes) async {
    appendCount += 1;
    await inner.appendBytes(path, bytes);
  }

  @override
  Future<FsStat> stat(String path) => inner.stat(path);

  @override
  Future<void> ensureDir(String path) => inner.ensureDir(path);

  @override
  Future<void> removeRecursive(String path) => inner.removeRecursive(path);

  @override
  Future<void> rename(String from, String to) => inner.rename(from, to);

  @override
  Future<String?> readString(String path) => inner.readString(path);

  @override
  Future<List<int>?> readBytes(String path) => inner.readBytes(path);

  @override
  Future<void> writeString(String path, String content) =>
      inner.writeString(path, content);

  @override
  Future<void> writeBytes(String path, List<int> bytes) =>
      inner.writeBytes(path, bytes);

  @override
  Future<List<int>?> readBytesRange(String path, int offset, int length) =>
      inner.readBytesRange(path, offset, length);

  @override
  Future<void> atomicWrite(String path, String content) =>
      inner.atomicWrite(path, content);

  @override
  Future<List<FsDirEntry>> listDir(String path) => inner.listDir(path);

  @override
  Future<bool> createSymlink({
    required String target,
    required String linkPath,
  }) => inner.createSymlink(target: target, linkPath: linkPath);

  @override
  Future<String?> readSymlinkTarget(String linkPath) =>
      inner.readSymlinkTarget(linkPath);

  @override
  Future<String?> resolveSymlink(String path) => inner.resolveSymlink(path);

  @override
  Future<void> copyTree({
    required String source,
    required String destination,
  }) => inner.copyTree(source: source, destination: destination);

  @override
  Future<void> copyFile(String source, String destination) =>
      inner.copyFile(source, destination);

  @override
  Future<List<FsDirEntry>> listDirRecursive(String path) =>
      inner.listDirRecursive(path);

  @override
  Future<String> createTempDir({String? prefix, String? parent}) =>
      inner.createTempDir(prefix: prefix, parent: parent);

  @override
  Future<void> appendString(String path, String content) =>
      inner.appendString(path, content);
}

/// Delegates every [Filesystem] method to [inner], except [appendBytes] which
/// fails after [failAfter] successful calls.
class _FailAfterAppends implements Filesystem {
  _FailAfterAppends(this.inner, {required this.failAfter});

  final Filesystem inner;
  final int failAfter;
  var _appends = 0;

  @override
  p.Context get pathContext => inner.pathContext;

  @override
  Future<void> appendBytes(String path, List<int> bytes) async {
    _appends += 1;
    if (_appends > failAfter) throw StateError('boom');
    await inner.appendBytes(path, bytes);
  }

  @override
  Future<FsStat> stat(String path) => inner.stat(path);

  @override
  Future<void> ensureDir(String path) => inner.ensureDir(path);

  @override
  Future<void> removeRecursive(String path) => inner.removeRecursive(path);

  @override
  Future<void> rename(String from, String to) => inner.rename(from, to);

  @override
  Future<String?> readString(String path) => inner.readString(path);

  @override
  Future<List<int>?> readBytes(String path) => inner.readBytes(path);

  @override
  Future<void> writeString(String path, String content) =>
      inner.writeString(path, content);

  @override
  Future<void> writeBytes(String path, List<int> bytes) =>
      inner.writeBytes(path, bytes);

  @override
  Future<List<int>?> readBytesRange(String path, int offset, int length) =>
      inner.readBytesRange(path, offset, length);

  @override
  Future<void> atomicWrite(String path, String content) =>
      inner.atomicWrite(path, content);

  @override
  Future<List<FsDirEntry>> listDir(String path) => inner.listDir(path);

  @override
  Future<bool> createSymlink({
    required String target,
    required String linkPath,
  }) => inner.createSymlink(target: target, linkPath: linkPath);

  @override
  Future<String?> readSymlinkTarget(String linkPath) =>
      inner.readSymlinkTarget(linkPath);

  @override
  Future<String?> resolveSymlink(String path) => inner.resolveSymlink(path);

  @override
  Future<void> copyTree({
    required String source,
    required String destination,
  }) => inner.copyTree(source: source, destination: destination);

  @override
  Future<void> copyFile(String source, String destination) =>
      inner.copyFile(source, destination);

  @override
  Future<List<FsDirEntry>> listDirRecursive(String path) =>
      inner.listDirRecursive(path);

  @override
  Future<String> createTempDir({String? prefix, String? parent}) =>
      inner.createTempDir(prefix: prefix, parent: parent);

  @override
  Future<void> appendString(String path, String content) =>
      inner.appendString(path, content);
}

/// Member A publishes on `local`; member B fetches on `ssh:hostB`. Two fake
/// filesystems stand in for the two machines.
class _Fixture {
  _Fixture({int chunkSize = ArtifactTransferService.defaultChunkSize}) {
    service = ArtifactTransferService(
      registry: ArtifactRegistry(),
      resolveFs: (targetId) async => _fsByTarget[targetId]!,
      targetForMember: (memberId) => _targetByMember[memberId]!,
      inboxDirFor: (memberId) => _inboxByMember[memberId]!,
      chunkSize: chunkSize,
    );
  }

  final InMemoryFilesystem publisherFs = InMemoryFilesystem();
  final InMemoryFilesystem fetcherFs = InMemoryFilesystem();

  late final Map<String, Filesystem> _fsByTarget = {
    'local': publisherFs,
    'ssh:hostB': fetcherFs,
  };
  final Map<String, String> _targetByMember = {'A': 'local', 'B': 'ssh:hostB'};
  final Map<String, String> _inboxByMember = {
    'A': '/home/a/inbox',
    'B': '/remote/sessions/s1/runtime/members/B/inbox',
  };

  late final ArtifactTransferService service;

  Future<void> seedSource(
    List<int> bytes, {
    String path = '/work/out.bin',
  }) async {
    await publisherFs.writeBytes(path, bytes);
  }
}

void main() {
  group('ArtifactTransferService', () {
    test(
      'happy path: publish then fetch moves bytes and returns final path',
      () async {
        final f = _Fixture();
        final bytes = List<int>.generate(64, (i) => i);
        await f.seedSource(bytes);

        await f.service.publish(
          publisherMemberId: 'A',
          path: '/work/out.bin',
          name: 'out',
        );

        final result = await f.service.fetch(
          fetcherMemberId: 'B',
          name: 'out',
          destPath: 'delivered.bin',
        );

        final landed =
            '/remote/sessions/s1/runtime/members/B/inbox/delivered.bin';
        expect(result.finalPath, landed);
        expect(result.sizeBytes, 64);
        expect(result.publisherMemberId, 'A');
        expect(await f.fetcherFs.readBytes(landed), bytes);
        // publisher file untouched (read-only on its machine).
        expect(await f.publisherFs.readBytes('/work/out.bin'), bytes);
      },
    );

    test('unknown name throws', () async {
      final f = _Fixture();
      expect(
        () =>
            f.service.fetch(fetcherMemberId: 'B', name: 'ghost', destPath: 'x'),
        throwsA(isA<UnknownArtifactException>()),
      );
    });

    test('multi-chunk fetch copies full payload', () async {
      final f = _Fixture(chunkSize: 4);
      final bytes = List<int>.generate(10, (i) => i);
      await f.seedSource(bytes);
      await f.service.publish(
        publisherMemberId: 'A',
        path: '/work/out.bin',
        name: 'out',
      );
      final r = await f.service.fetch(
        fetcherMemberId: 'B',
        name: 'out',
        destPath: 'delivered.bin',
      );
      expect(await f.fetcherFs.readBytes(r.finalPath), bytes);
      expect(
        await f.fetcherFs.stat('${r.finalPath}.tp-partial'),
        predicate<FsStat>((s) => !s.exists),
      );
    });

    test('zero-byte cross-machine fetch creates empty dest', () async {
      final f = _Fixture(chunkSize: 4);
      await f.seedSource(<int>[]);
      await f.service.publish(
        publisherMemberId: 'A',
        path: '/work/out.bin',
        name: 'empty',
      );
      final r = await f.service.fetch(
        fetcherMemberId: 'B',
        name: 'empty',
        destPath: 'empty.bin',
      );
      expect(r.sizeBytes, 0);
      expect(await f.fetcherFs.readBytes(r.finalPath), <int>[]);
      expect((await f.fetcherFs.stat('${r.finalPath}.tp-partial')).exists, isFalse);
    });

    test('resume continues from partial after interrupt', () async {
      final bytes = List<int>.generate(12, (i) => i);
      final publisherFs = InMemoryFilesystem();
      final fetcherInner = InMemoryFilesystem();
      final fetcherFs = _FailAfterAppends(fetcherInner, failAfter: 1);
      final service = ArtifactTransferService(
        registry: ArtifactRegistry(),
        resolveFs: (id) async => id == 'local' ? publisherFs : fetcherFs,
        targetForMember: (m) => m == 'A' ? 'local' : 'ssh:hostB',
        inboxDirFor: (m) => m == 'A'
            ? '/home/a/inbox'
            : '/remote/sessions/s1/runtime/members/B/inbox',
        chunkSize: 4,
      );
      await publisherFs.writeBytes('/work/out.bin', bytes);
      await service.publish(
        publisherMemberId: 'A',
        path: '/work/out.bin',
        name: 'out',
      );

      await expectLater(
        () => service.fetch(
          fetcherMemberId: 'B',
          name: 'out',
          destPath: 'delivered.bin',
        ),
        throwsA(isA<StateError>()),
      );

      final dest =
          '/remote/sessions/s1/runtime/members/B/inbox/delivered.bin';
      expect((await fetcherInner.stat('$dest.tp-partial')).exists, isTrue);

      // Second attempt uses a clean wrapper (no fail) on the same store.
      final service2 = ArtifactTransferService(
        registry: service.registry,
        resolveFs: (id) async => id == 'local' ? publisherFs : fetcherInner,
        targetForMember: (m) => m == 'A' ? 'local' : 'ssh:hostB',
        inboxDirFor: (m) => m == 'A'
            ? '/home/a/inbox'
            : '/remote/sessions/s1/runtime/members/B/inbox',
        chunkSize: 4,
      );
      final r = await service2.fetch(
        fetcherMemberId: 'B',
        name: 'out',
        destPath: 'delivered.bin',
      );
      expect(await fetcherInner.readBytes(r.finalPath), bytes);
    });

    test('resume trusts meta when partial stat size is null', () async {
      final bytes = List<int>.generate(12, (i) => i);
      final publisherFs = InMemoryFilesystem();
      final fetcherInner = InMemoryFilesystem();
      final counting = _CountingAppends(_StatWithoutSize(fetcherInner));
      final service = ArtifactTransferService(
        registry: ArtifactRegistry(),
        resolveFs: (id) async => id == 'local' ? publisherFs : counting,
        targetForMember: (m) => m == 'A' ? 'local' : 'ssh:hostB',
        inboxDirFor: (m) => m == 'A'
            ? '/home/a/inbox'
            : '/remote/sessions/s1/runtime/members/B/inbox',
        chunkSize: 4,
      );
      await publisherFs.writeBytes('/work/out.bin', bytes);
      await service.publish(
        publisherMemberId: 'A',
        path: '/work/out.bin',
        name: 'out',
      );

      final dest =
          '/remote/sessions/s1/runtime/members/B/inbox/delivered.bin';
      await fetcherInner.writeBytes('$dest.tp-partial', bytes.sublist(0, 4));
      await fetcherInner.writeString(
        '$dest.tp-partial.meta.json',
        '{"artifactName":"out","publisherMemberId":"A","sourceTargetId":"local",'
        '"sourcePath":"/work/out.bin","expectedSizeBytes":12,"bytesWritten":4,'
        '"chunkSize":4}',
      );

      final r = await service.fetch(
        fetcherMemberId: 'B',
        name: 'out',
        destPath: 'delivered.bin',
      );
      expect(await fetcherInner.readBytes(r.finalPath), bytes);
      // Resume appends the remaining 8 bytes in 2 chunks; a full restart would
      // append 3 chunks (partialStat.size ?? 0 → length mismatch).
      expect(counting.appendCount, 2);
    });

    test('mismatched meta discards partial and restarts', () async {
      final f = _Fixture(chunkSize: 4);
      final bytes = List<int>.generate(8, (i) => i);
      await f.seedSource(bytes);
      await f.service.publish(
        publisherMemberId: 'A',
        path: '/work/out.bin',
        name: 'out',
      );
      final dest =
          '/remote/sessions/s1/runtime/members/B/inbox/delivered.bin';
      await f.fetcherFs.writeBytes('$dest.tp-partial', [9, 9, 9, 9]);
      await f.fetcherFs.writeString(
        '$dest.tp-partial.meta.json',
        // identity that will not match (wrong sourcePath)
        '{"artifactName":"out","publisherMemberId":"A","sourceTargetId":"local",'
        '"sourcePath":"/work/OTHER.bin","expectedSizeBytes":8,"bytesWritten":4,'
        '"chunkSize":4}',
      );
      final r = await f.service.fetch(
        fetcherMemberId: 'B',
        name: 'out',
        destPath: 'delivered.bin',
      );
      expect(await f.fetcherFs.readBytes(r.finalPath), bytes);
    });

    test('complete partial retries rename only', () async {
      final f = _Fixture(chunkSize: 4);
      final bytes = List<int>.generate(8, (i) => i);
      await f.seedSource(bytes);
      await f.service.publish(
        publisherMemberId: 'A',
        path: '/work/out.bin',
        name: 'out',
      );
      final dest =
          '/remote/sessions/s1/runtime/members/B/inbox/delivered.bin';
      await f.fetcherFs.writeBytes('$dest.tp-partial', bytes);
      await f.fetcherFs.writeString(
        '$dest.tp-partial.meta.json',
        '{"artifactName":"out","publisherMemberId":"A","sourceTargetId":"local",'
        '"sourcePath":"/work/out.bin","expectedSizeBytes":8,"bytesWritten":8,'
        '"chunkSize":4}',
      );
      final r = await f.service.fetch(
        fetcherMemberId: 'B',
        name: 'out',
        destPath: 'delivered.bin',
      );
      expect(r.finalPath, dest);
      expect(await f.fetcherFs.readBytes(dest), bytes);
      expect((await f.fetcherFs.stat('$dest.tp-partial')).exists, isFalse);
    });

    test('same-machine uses copyFile and clears partials', () async {
      final shared = InMemoryFilesystem();
      final registry = ArtifactRegistry();
      final service = ArtifactTransferService(
        registry: registry,
        resolveFs: (_) async => shared,
        targetForMember: (_) => 'local',
        inboxDirFor: (_) => '/inbox',
        chunkSize: 4,
      );
      final bytes = [1, 2, 3, 4, 5];
      await shared.writeBytes('/work/out.bin', bytes);
      await shared.writeBytes('/inbox/out.bin.tp-partial', [9]);
      await shared.writeString('/inbox/out.bin.tp-partial.meta.json', '{}');
      await service.publish(
        publisherMemberId: 'A',
        path: '/work/out.bin',
        name: 'out',
      );
      final r = await service.fetch(
        fetcherMemberId: 'B',
        name: 'out',
        destPath: 'out.bin',
      );
      expect(r.finalPath, '/inbox/out.bin');
      expect(await shared.readBytes('/inbox/out.bin'), bytes);
      expect((await shared.stat('/inbox/out.bin.tp-partial')).exists, isFalse);
      expect(
        (await shared.stat('/inbox/out.bin.tp-partial.meta.json')).exists,
        isFalse,
      );
    });

    test('source shrink mid-transfer discards partial', () async {
      final f = _Fixture(chunkSize: 4);
      final bytes = List<int>.generate(12, (i) => i);
      await f.seedSource(bytes);
      await f.service.publish(
        publisherMemberId: 'A',
        path: '/work/out.bin',
        name: 'out',
      );
      final dest =
          '/remote/sessions/s1/runtime/members/B/inbox/delivered.bin';
      await f.fetcherFs.writeBytes(
        '$dest.tp-partial',
        bytes.sublist(0, 8),
      );
      await f.fetcherFs.writeString(
        '$dest.tp-partial.meta.json',
        '{"artifactName":"out","publisherMemberId":"A","sourceTargetId":"local",'
        '"sourcePath":"/work/out.bin","expectedSizeBytes":12,"bytesWritten":8,'
        '"chunkSize":4}',
      );
      // Shrink source below bytesWritten.
      await f.publisherFs.writeBytes('/work/out.bin', bytes.sublist(0, 4));
      await expectLater(
        () => f.service.fetch(
          fetcherMemberId: 'B',
          name: 'out',
          destPath: 'delivered.bin',
        ),
        throwsA(isA<ArtifactSourceChangedException>()),
      );
      expect((await f.fetcherFs.stat('$dest.tp-partial')).exists, isFalse);
      expect(
        (await f.fetcherFs.stat('$dest.tp-partial.meta.json')).exists,
        isFalse,
      );
    });

    test(
      'dest exists without overwrite throws; with overwrite succeeds',
      () async {
        final f = _Fixture();
        await f.seedSource([1, 2, 3]);
        await f.service.publish(
          publisherMemberId: 'A',
          path: '/work/out.bin',
          name: 'out',
        );

        final dest = '/remote/sessions/s1/runtime/members/B/inbox/out.bin';
        await f.fetcherFs.writeBytes(dest, [9, 9]);

        expect(
          () => f.service.fetch(
            fetcherMemberId: 'B',
            name: 'out',
            destPath: 'out.bin',
          ),
          throwsA(isA<ArtifactDestinationExistsException>()),
        );

        final result = await f.service.fetch(
          fetcherMemberId: 'B',
          name: 'out',
          destPath: 'out.bin',
          overwrite: true,
        );
        expect(result.finalPath, dest);
        expect(await f.fetcherFs.readBytes(dest), [1, 2, 3]);
      },
    );

    test('dest escaping the inbox throws', () async {
      final f = _Fixture();
      await f.seedSource([1]);
      await f.service.publish(
        publisherMemberId: 'A',
        path: '/work/out.bin',
        name: 'out',
      );

      expect(
        () => f.service.fetch(
          fetcherMemberId: 'B',
          name: 'out',
          destPath: '../escape.bin',
        ),
        throwsA(isA<ArtifactDestinationOutsideInboxException>()),
      );
    });

    test('publish rejects a non-file source', () async {
      final f = _Fixture();
      // no file seeded → stat reports notFound
      expect(
        () => f.service.publish(
          publisherMemberId: 'A',
          path: '/work/missing.bin',
          name: 'out',
        ),
        throwsA(isA<ArtifactSourceNotFileException>()),
      );
    });
  });
}
