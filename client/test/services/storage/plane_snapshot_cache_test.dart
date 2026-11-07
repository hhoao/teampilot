import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/storage/plane_snapshot_cache.dart';

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
}
