import 'models.dart';
import 'summary_format.dart';
import 'trace_decoder.dart';

/// How a [FlutterFrame] lines up with decoded Perfetto timeline data.
enum FrameTraceCoverage {
  /// `uiFrameBeginNs` has an entry for this frame number.
  marker,

  /// No marker, but [FlutterFrame.startTimeUs] overlaps trace slice timestamps.
  timestampOverlap,

  /// Frame timing falls outside the trace slice time span.
  outOfRange,

  /// Trace has no slices at all.
  noTrace,
}

class TraceTimeSpan {
  const TraceTimeSpan({required this.beginNs, required this.endNs});

  final int beginNs;
  final int endNs;

  int get beginUs => beginNs ~/ 1000;
  int get endUs => endNs ~/ 1000;
  double get durationMs => (endNs - beginNs) / 1e6;
}

class TraceCoverageSummary {
  const TraceCoverageSummary({
    required this.sliceSpan,
    required this.markerFrameNumbers,
    this.uiTrackName,
  });

  final TraceTimeSpan? sliceSpan;
  final List<int> markerFrameNumbers;
  final String? uiTrackName;

  int? get firstMarkerFrame =>
      markerFrameNumbers.isEmpty ? null : markerFrameNumbers.first;

  int? get lastMarkerFrame =>
      markerFrameNumbers.isEmpty ? null : markerFrameNumbers.last;
}

TraceCoverageSummary traceCoverageSummary(DecodedTrace trace) {
  if (trace.slices.isEmpty) {
    return TraceCoverageSummary(
      sliceSpan: null,
      markerFrameNumbers: _sortedMarkerFrames(trace),
      uiTrackName: trace.uiTrackUuid != null
          ? trace.tracks[trace.uiTrackUuid]
          : null,
    );
  }

  var beginNs = trace.slices.first.startNs;
  var endNs = trace.slices.first.endNs;
  for (final slice in trace.slices) {
    if (slice.startNs < beginNs) beginNs = slice.startNs;
    if (slice.endNs > endNs) endNs = slice.endNs;
  }

  return TraceCoverageSummary(
    sliceSpan: TraceTimeSpan(beginNs: beginNs, endNs: endNs),
    markerFrameNumbers: _sortedMarkerFrames(trace),
    uiTrackName: trace.uiTrackUuid != null
        ? trace.tracks[trace.uiTrackUuid]
        : null,
  );
}

List<int> _sortedMarkerFrames(DecodedTrace trace) {
  return trace.uiFrameBeginNs.keys.toList()..sort();
}

FrameTraceCoverage frameTraceCoverage(
  FlutterFrame frame,
  TraceCoverageSummary coverage,
) {
  if (coverage.sliceSpan == null) return FrameTraceCoverage.noTrace;

  if (coverage.markerFrameNumbers.contains(frame.number)) {
    return FrameTraceCoverage.marker;
  }

  final startNs = frame.startTimeUs * 1000;
  final endNs = (frame.startTimeUs + frame.elapsedUs) * 1000;
  final span = coverage.sliceSpan!;
  if (endNs >= span.beginNs && startNs <= span.endNs) {
    return FrameTraceCoverage.timestampOverlap;
  }

  return FrameTraceCoverage.outOfRange;
}

bool frameHasTraceSlices(
  FlutterFrame frame,
  DecodedTrace trace,
  TraceCoverageSummary coverage,
) {
  if (frameTraceCoverage(frame, coverage) == FrameTraceCoverage.outOfRange) {
    return false;
  }
  return slicesForFrame(
        trace: trace,
        frameNumber: frame.number,
        startTimeUs: frame.startTimeUs,
        elapsedUs: frame.elapsedUs,
      ).isNotEmpty;
}

/// Janky frames that overlap trace data, ordered slowest first.
List<FlutterFrame> tracedJankyFrames({
  required List<FlutterFrame> jankyFrames,
  required DecodedTrace trace,
  required TraceCoverageSummary coverage,
}) {
  final traced = <FlutterFrame>[];
  for (final frame in jankyFrames) {
    if (frameHasTraceSlices(frame, trace, coverage)) {
      traced.add(frame);
    }
  }
  return traced;
}

/// Slowest janky frame with timeline slices, if any.
FlutterFrame? slowestTracedJankyFrame({
  required List<FlutterFrame> jankyFrames,
  required DecodedTrace trace,
  required TraceCoverageSummary coverage,
}) {
  final traced = tracedJankyFrames(
    jankyFrames: jankyFrames,
    trace: trace,
    coverage: coverage,
  );
  if (traced.isEmpty) return null;
  return traced.first;
}

String formatTraceCoverageWarning({
  required FlutterFrame frame,
  required TraceCoverageSummary coverage,
  int? suggestedFrameNumber,
  List<int> precisionFrameNumbers = const [],
}) {
  final lastMarker = coverage.lastMarkerFrame;
  final span = coverage.sliceSpan;
  final buffer = StringBuffer()
    ..writeln(
      'Frame #${frame.number}: '
      '${frame.elapsedMs.toStringAsFixed(1)} ms '
      '(build ${frame.buildMs.toStringAsFixed(1)}, '
      'raster ${frame.rasterMs.toStringAsFixed(1)}). '
      'No timeline slices in export.',
    );

  if (span != null && lastMarker != null) {
    buffer.writeln(
      'traceBinary: ~${span.durationMs.toStringAsFixed(0)} ms, '
      'UI markers #${coverage.firstMarkerFrame}–#$lastMarker.',
    );
  } else if (lastMarker != null) {
    buffer.writeln(
      'UI frame markers in trace: '
      '#${coverage.firstMarkerFrame}–#$lastMarker.',
    );
  } else {
    buffer.writeln('No UI frame markers in traceBinary.');
  }

  if (precisionFrameNumbers.isNotEmpty) {
    buffer.writeln(
      'Precision hot paths: frames ${formatFrameList(precisionFrameNumbers)} '
      '(frame #${frame.number} not included).',
    );
  } else {
    buffer.writeln('Precision hot paths: frame #${frame.number} not included.');
  }

  if (suggestedFrameNumber != null) {
    buffer.write(
      'Slowest janky frame with timeline data in export: '
      '#$suggestedFrameNumber.',
    );
  }

  return buffer.toString().trimRight();
}
