import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team_bus/artifacts/artifact_partial_meta.dart';

void main() {
  final base = ArtifactPartialMeta(
    artifactName: 'jar',
    publisherMemberId: 'A',
    sourceTargetId: 'local',
    sourcePath: '/work/a.jar',
    expectedSizeBytes: 100,
    sourceMtimeMs: 50,
    bytesWritten: 40,
    chunkSize: 4 << 20,
  );

  test('matches when identity size mtime and length agree', () {
    expect(
      base.matchesLive(
        artifactName: 'jar',
        publisherMemberId: 'A',
        sourceTargetId: 'local',
        sourcePath: '/work/a.jar',
        liveSizeBytes: 100,
        liveMtimeMs: 50,
        partialLength: 40,
      ),
      isTrue,
    );
  });

  test('rejects identity or length mismatch', () {
    expect(
      base.matchesLive(
        artifactName: 'other',
        publisherMemberId: 'A',
        sourceTargetId: 'local',
        sourcePath: '/work/a.jar',
        liveSizeBytes: 100,
        liveMtimeMs: 50,
        partialLength: 40,
      ),
      isFalse,
    );
    expect(
      base.matchesLive(
        artifactName: 'jar',
        publisherMemberId: 'A',
        sourceTargetId: 'local',
        sourcePath: '/work/a.jar',
        liveSizeBytes: 100,
        liveMtimeMs: 50,
        partialLength: 39,
      ),
      isFalse,
    );
  });

  test('rejects when both sides have mtime and they differ', () {
    expect(
      base.matchesLive(
        artifactName: 'jar',
        publisherMemberId: 'A',
        sourceTargetId: 'local',
        sourcePath: '/work/a.jar',
        liveSizeBytes: 100,
        liveMtimeMs: 99,
        partialLength: 40,
      ),
      isFalse,
    );
  });

  test('json round-trip', () {
    final again = ArtifactPartialMeta.fromJson(base.toJson());
    expect(again.artifactName, base.artifactName);
    expect(again.bytesWritten, 40);
  });
}
