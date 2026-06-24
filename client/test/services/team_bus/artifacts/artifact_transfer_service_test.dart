import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/team_bus/artifacts/artifact_exceptions.dart';
import 'package:teampilot/services/team_bus/artifacts/artifact_registry.dart';
import 'package:teampilot/services/team_bus/artifacts/artifact_transfer_service.dart';

import '../../../support/in_memory_filesystem.dart';

/// Member A publishes on `local`; member B fetches on `ssh:hostB`. Two fake
/// filesystems stand in for the two machines.
class _Fixture {
  _Fixture({int maxBytes = ArtifactTransferService.defaultMaxBytes}) {
    service = ArtifactTransferService(
      registry: ArtifactRegistry(),
      resolveFs: (targetId) async => _fsByTarget[targetId]!,
      targetForMember: (memberId) => _targetByMember[memberId]!,
      inboxDirFor: (memberId) => _inboxByMember[memberId]!,
      maxBytes: maxBytes,
    );
  }

  final InMemoryFilesystem publisherFs = InMemoryFilesystem();
  final InMemoryFilesystem fetcherFs = InMemoryFilesystem();

  late final Map<String, Filesystem> _fsByTarget = {
    'local': publisherFs,
    'ssh:hostB': fetcherFs,
  };
  final Map<String, String> _targetByMember = {
    'A': 'local',
    'B': 'ssh:hostB',
  };
  final Map<String, String> _inboxByMember = {
    'A': '/home/a/inbox',
    'B': '/remote/sessions/s1/runtime/members/B/inbox',
  };

  late final ArtifactTransferService service;

  Future<void> seedSource(List<int> bytes,
      {String path = '/work/out.bin'}) async {
    await publisherFs.writeBytes(path, bytes);
  }
}

void main() {
  group('ArtifactTransferService', () {
    test('happy path: publish then fetch moves bytes and returns final path',
        () async {
      final f = _Fixture();
      final bytes = List<int>.generate(64, (i) => i);
      await f.seedSource(bytes);

      await f.service
          .publish(publisherMemberId: 'A', path: '/work/out.bin', name: 'out');

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
    });

    test('unknown name throws', () async {
      final f = _Fixture();
      expect(
        () =>
            f.service.fetch(fetcherMemberId: 'B', name: 'ghost', destPath: 'x'),
        throwsA(isA<UnknownArtifactException>()),
      );
    });

    test('over-cap transfer throws', () async {
      final f = _Fixture(maxBytes: 8);
      await f.seedSource(List<int>.filled(32, 1));
      await f.service
          .publish(publisherMemberId: 'A', path: '/work/out.bin', name: 'big');

      expect(
        () => f.service
            .fetch(fetcherMemberId: 'B', name: 'big', destPath: 'big.bin'),
        throwsA(isA<ArtifactTooLargeException>()),
      );
    });

    test('dest exists without overwrite throws; with overwrite succeeds',
        () async {
      final f = _Fixture();
      await f.seedSource([1, 2, 3]);
      await f.service
          .publish(publisherMemberId: 'A', path: '/work/out.bin', name: 'out');

      final dest = '/remote/sessions/s1/runtime/members/B/inbox/out.bin';
      await f.fetcherFs.writeBytes(dest, [9, 9]);

      expect(
        () => f.service
            .fetch(fetcherMemberId: 'B', name: 'out', destPath: 'out.bin'),
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
    });

    test('dest escaping the inbox throws', () async {
      final f = _Fixture();
      await f.seedSource([1]);
      await f.service
          .publish(publisherMemberId: 'A', path: '/work/out.bin', name: 'out');

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
