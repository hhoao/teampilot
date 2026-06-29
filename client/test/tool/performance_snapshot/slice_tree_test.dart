import 'package:flutter_test/flutter_test.dart';

import '../../../tool/performance_snapshot/slice_tree.dart';
import '../../../tool/performance_snapshot/trace_decoder.dart';

void main() {
  test('buildSliceForest empty returns mutable list', () {
    final roots = buildSliceForest(const []);
    expect(roots, isEmpty);
    expect(() => pruneSliceTreeMinTotal(roots, 0.1), returnsNormally);
  });

  test('pruneSliceTreeMinTotal removes small nodes', () {
    final roots = [
      SliceTreeNode(
        TraceSlice(
          name: 'BUILD',
          category: 'Dart',
          track: 'io.flutter.ui',
          startNs: 0,
          durationNs: 1000000,
        ),
      ),
      SliceTreeNode(
        TraceSlice(
          name: 'tiny',
          category: 'Dart',
          track: 'io.flutter.ui',
          startNs: 0,
          durationNs: 100000,
        ),
      ),
    ];
    pruneSliceTreeMinTotal(roots, 0.2);
    expect(roots.length, 1);
    expect(roots.first.slice.name, 'BUILD');
  });
}
