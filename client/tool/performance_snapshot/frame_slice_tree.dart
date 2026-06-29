import 'dart_slice_analysis.dart';
import 'models.dart';
import 'slice_tree.dart';
import 'trace_decoder.dart';
import 'trace_filters.dart';

/// Dominant phase in a janky frame (from flutterFrames timings).
String frameBottleneck(FlutterFrame frame) {
  final parts = {
    'build': frame.buildMs,
    'raster': frame.rasterMs,
    'vsync': frame.vsyncMs,
  };
  final max = parts.entries.reduce((a, b) => a.value > b.value ? a : b);
  if (max.value < frame.elapsedMs * 0.4) return 'mixed/idle';
  return max.key;
}

/// Which timeline track(s) to prioritize when investigating this frame.
String primaryAnalysisTrack(FlutterFrame frame) {
  return switch (frameBottleneck(frame)) {
    'raster' => 'raster',
    'build' => 'ui',
    'vsync' => 'ui',
    _ => 'both',
  };
}

enum FlameTreeTrack { ui, raster, dart, both }

bool isDartFlameTreeSlice(TraceSlice slice) => isDartMethodSlice(slice);

bool isUiFlameTreeSlice(TraceSlice slice) {
  if (slice.isShaderEvent) return false;
  if (slice.track.contains('.ui')) return true;
  if (slice.category == 'Dart' && slice.name == 'Frame') return true;
  return false;
}

bool isRasterFlameTreeSlice(TraceSlice slice) {
  if (slice.isShaderEvent) return false;
  if (slice.track.contains('.raster')) return true;
  if (slice.track.contains('.platform')) return true;
  if (slice.name == rasterEventName) return true;
  return false;
}

bool isFlameTreeSlice(TraceSlice slice, FlameTreeTrack track) => switch (track) {
      FlameTreeTrack.ui => isUiFlameTreeSlice(slice),
      FlameTreeTrack.raster => isRasterFlameTreeSlice(slice),
      FlameTreeTrack.dart => isDartFlameTreeSlice(slice),
      FlameTreeTrack.both =>
        isUiFlameTreeSlice(slice) ||
        isRasterFlameTreeSlice(slice) ||
        isDartFlameTreeSlice(slice),
    };

List<TraceSlice> slicesInFrameWindow({
  required DecodedTrace trace,
  required FlutterFrame frame,
  required TraceFilters filters,
}) {
  return filters.applySlices(
    slicesForFrame(
      trace: trace,
      frameNumber: frame.number,
      startTimeUs: frame.startTimeUs,
      elapsedUs: frame.elapsedUs,
    ),
  );
}

List<SliceTreeNode> buildFlameForestForTrack(
  List<TraceSlice> inWindow,
  FlameTreeTrack track,
) {
  final flameSlices = inWindow.where((s) => isFlameTreeSlice(s, track)).toList();
  var roots = buildSliceForest(flameSlices);
  dropRedundantDartFrameRoots(roots);
  return roots;
}

/// Hides the coarse Dart `Frame` slice when finer `io.flutter.ui` roots exist.
void dropRedundantDartFrameRoots(List<SliceTreeNode> roots) {
  final hasUi = roots.any((r) => r.slice.track.contains('.ui'));
  if (!hasUi) return;
  roots.removeWhere(
    (r) => r.slice.category == 'Dart' && r.slice.name == 'Frame',
  );
}

List<SliceSelfTimeEntry> collectFrameSelfTimeHotspots({
  required DecodedTrace trace,
  required FlutterFrame frame,
  required TraceFilters filters,
  required FlameTreeTrack track,
  double minSelfMs = 0.3,
  int limit = 50,
}) {
  final inWindow = slicesInFrameWindow(
    trace: trace,
    frame: frame,
    filters: filters,
  );
  final roots = buildFlameForestForTrack(inWindow, track);
  return collectSelfTimeHotspots(
    roots,
    minSelfMs: minSelfMs,
    limit: limit,
  );
}

String trackLabelForFlameTree(FlameTreeTrack track) => switch (track) {
      FlameTreeTrack.ui => 'ui',
      FlameTreeTrack.raster => 'raster',
      FlameTreeTrack.dart => 'dart',
      FlameTreeTrack.both => 'both',
    };

String? inferPhaseFromPath(String path) {
  final upper = path.toUpperCase();
  for (final phase in [
    'BUILD',
    'LAYOUT',
    'PAINT',
    'COMPOSITING',
    'RASTER',
  ]) {
    if (upper.contains(phase)) return phase;
  }
  return null;
}
