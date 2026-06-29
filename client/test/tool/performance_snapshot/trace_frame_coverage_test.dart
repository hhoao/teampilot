import 'package:flutter_test/flutter_test.dart';

import '../../../tool/performance_snapshot/models.dart';
import '../../../tool/performance_snapshot/trace_frame_coverage.dart';

void main() {
  group('formatTraceCoverageWarning', () {
    test('states frame scope for precision hot paths', () {
      final frame = const FlutterFrame(
        number: 2061,
        startTimeUs: 0,
        elapsedUs: 1286700,
        buildUs: 1280700,
        rasterUs: 4000,
        vsyncUs: 0,
      );
      final coverage = TraceCoverageSummary(
        sliceSpan: TraceTimeSpan(beginNs: 0, endNs: 2236000000),
        markerFrameNumbers: [2050, 2051, 2052, 2053, 2054, 2055, 2056, 2057, 2058, 2059],
      );

      final message = formatTraceCoverageWarning(
        frame: frame,
        coverage: coverage,
        suggestedFrameNumber: 2050,
        precisionFrameNumbers: [2050, 2052, 2056, 2058, 2059],
      );

      expect(message, contains('Frame #2061:'));
      expect(message, contains('No timeline slices in export'));
      expect(message, contains('frame #2061 not included'));
      expect(message, contains('Slowest janky frame with timeline data'));
      expect(message, contains('#2050'));
    });
  });
}
