import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/storage/home_runtime_identity.dart';
import 'package:teampilot/services/storage/plane_snapshot_cache.dart';

const _planeA = HomeRuntimeIdentity(targetId: 'local', appDataRoot: '/plane-a');
const _planeB = HomeRuntimeIdentity(
  targetId: 'ssh:studio',
  appDataRoot: '/plane-b',
);

void main() {
  test('starts empty', () {
    final cache = PlaneSnapshotCache<int>();

    expect(cache.snapshot, isNull);
  });

  test('write freezes a copy and returns the stored snapshot', () {
    final source = [1, 2, 3];
    final cache = PlaneSnapshotCache<int>();

    final stored = cache.write(source);
    source.add(4);

    expect(stored, [1, 2, 3]);
    expect(cache.snapshot, [1, 2, 3]);
    expect(identical(cache.snapshot, stored), isTrue);
    expect(() => stored.add(5), throwsUnsupportedError);
  });

  test('a second write replaces the snapshot', () {
    final cache = PlaneSnapshotCache<String>()
      ..write(['a'])
      ..write(['b', 'c']);

    expect(cache.snapshot, ['b', 'c']);
  });

  test('invalidate drops the snapshot', () {
    final cache = PlaneSnapshotCache<int>()..write([1]);

    cache.invalidate();

    expect(cache.snapshot, isNull);
  });

  group('plane binding', () {
    test('snapshot is dropped when the plane changes', () {
      var plane = _planeA;
      final cache = PlaneSnapshotCache<int>(plane: () => plane)..write([1]);

      expect(cache.snapshot, [1]);

      plane = _planeB;
      expect(cache.snapshot, isNull);

      // The dropped snapshot is gone for good: returning to plane A is cold.
      plane = _planeA;
      expect(cache.snapshot, isNull);
    });

    test('write from a non-current plane is not installed', () {
      var plane = _planeA;
      final cache = PlaneSnapshotCache<int>(plane: () => plane);

      // A load that started on plane B completes after the swap to A.
      final stored = cache.write([1], forPlane: _planeB);

      expect(stored, [1], reason: 'the caller still gets its frozen result');
      expect(cache.snapshot, isNull, reason: 'plane A must stay cold');
    });

    test('a write under the current plane is installed', () {
      var plane = _planeA;
      final cache = PlaneSnapshotCache<int>(plane: () => plane);

      cache.write([1], forPlane: _planeA);

      expect(cache.snapshot, [1]);
    });

    test('invalidate clears the plane binding', () {
      var plane = _planeA;
      final cache = PlaneSnapshotCache<int>(plane: () => plane)..write([1]);

      cache.invalidate();

      expect(cache.snapshot, isNull);
      // The next write binds to whatever plane is current, so a later swap
      // invalidates it like any other snapshot.
      plane = _planeB;
      cache.write([2]);
      expect(cache.snapshot, [2]);
      plane = _planeA;
      expect(cache.snapshot, isNull);
    });

    test('identical plane identity keeps the value cache (I5)', () {
      var planeReads = 0;
      final cache = PlaneSnapshotCache<int>(
        plane: () {
          planeReads++;
          // Rebuilt value objects with equal fields are the same plane.
          return HomeRuntimeIdentity(
            targetId: _planeA.targetId,
            appDataRoot: _planeA.appDataRoot,
          );
        },
      )..write([1]);

      expect(cache.snapshot, [1]);
      expect(planeReads, greaterThan(0));
    });

    test('an unbound cache keeps its snapshot across writes', () {
      final cache = PlaneSnapshotCache<int>()..write([1]);

      expect(cache.snapshot, [1]);
    });
  });
}
