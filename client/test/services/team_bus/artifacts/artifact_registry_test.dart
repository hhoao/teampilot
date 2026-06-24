import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team_bus/artifacts/artifact_exceptions.dart';
import 'package:teampilot/services/team_bus/artifacts/artifact_handle.dart';
import 'package:teampilot/services/team_bus/artifacts/artifact_registry.dart';

ArtifactHandle _handle(
  String name, {
  String publisher = 'A',
  String targetId = 'local',
  String path = '/work/out.bin',
  int size = 10,
  int publishedAtMs = 0,
}) =>
    ArtifactHandle(
      name: name,
      publisherMemberId: publisher,
      targetId: targetId,
      absolutePath: path,
      sizeBytes: size,
      kind: ArtifactKind.file,
      publishedAtMs: publishedAtMs,
    );

void main() {
  group('ArtifactRegistry', () {
    test('register / list / byName', () {
      final registry = ArtifactRegistry();
      registry.register(_handle('build.zip'));
      registry.register(_handle('report.pdf', publisher: 'B'));

      expect(registry.list().map((h) => h.name),
          containsAll(['build.zip', 'report.pdf']));
      expect(registry.byName('build.zip')!.publisherMemberId, 'A');
      expect(registry.byName('report.pdf')!.publisherMemberId, 'B');
      expect(registry.byName('missing'), isNull);
    });

    test('collision: duplicate name rejected unless overwrite', () {
      final registry = ArtifactRegistry();
      registry.register(_handle('out.bin', size: 1));

      expect(
        () => registry.register(_handle('out.bin', size: 2)),
        throwsA(isA<ArtifactNameCollisionException>()),
      );
      // unchanged after the rejected publish
      expect(registry.byName('out.bin')!.sizeBytes, 1);

      registry.register(_handle('out.bin', size: 2), overwrite: true);
      expect(registry.byName('out.bin')!.sizeBytes, 2);
    });

    test('evictExpired drops handles older than the TTL', () {
      final registry = ArtifactRegistry(ttl: const Duration(minutes: 10));
      registry.register(_handle('old', publishedAtMs: 0));
      registry.register(_handle('fresh', publishedAtMs: 9 * 60 * 1000));

      // now = 11 minutes → 'old' is past TTL, 'fresh' (published @9m) is not.
      final evicted = registry.evictExpired(11 * 60 * 1000);
      expect(evicted, 1);
      expect(registry.byName('old'), isNull);
      expect(registry.byName('fresh'), isNotNull);
    });

    test('clear removes everything', () {
      final registry = ArtifactRegistry();
      registry.register(_handle('a'));
      registry.register(_handle('b'));
      registry.clear();
      expect(registry.list(), isEmpty);
    });
  });
}
