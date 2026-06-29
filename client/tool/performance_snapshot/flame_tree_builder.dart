import 'models.dart';
import 'options.dart';
import 'frame_slice_tree.dart';
import 'slice_tree.dart';
import 'trace_decoder.dart';
import 'trace_frame_coverage.dart';

/// Flame-chart-style nested slice tree for one Flutter frame.
class FlameTreeAnalysis {
  const FlameTreeAnalysis({
    required this.frame,
    required this.budgetMs,
    required this.timelineWindowMs,
    required this.roots,
    required this.topSelfTime,
    required this.sliceCountInWindow,
    required this.appliedFilters,
    this.forestOmitted,
    this.traceCoverageWarning,
    this.suggestedFrameNumber,
  });

  final FlutterFrame frame;
  final double budgetMs;
  final double? timelineWindowMs;
  final List<SliceTreeNode> roots;
  final List<SliceSelfTimeEntry> topSelfTime;
  final int sliceCountInWindow;
  final Map<String, Object?> appliedFilters;
  final SliceTreeForestOmitted? forestOmitted;
  final String? traceCoverageWarning;
  final int? suggestedFrameNumber;
}

FlameTreeAnalysis? buildFlameTreeAnalysis({
  required PerformanceSnapshot snapshot,
  required AnalyzeOptions options,
}) {
  final bytes = snapshot.traceBinary;
  if (bytes == null || bytes.isEmpty) return null;

  final budgetMs = snapshot.budgetMs(options);
  final trace = decodeTrace(bytes);
  final frame = _resolveFlameFrame(snapshot, options, budgetMs);
  if (frame == null) return null;

  final filters = options.traceFilters;
  final inWindow = slicesInFrameWindow(
    trace: trace,
    frame: frame,
    filters: filters,
  );

  final flameSlices = inWindow
      .where(
        (s) =>
            isUiFlameTreeSlice(s) ||
            isDartFlameTreeSlice(s),
      )
      .toList();

  var roots = [
    ...buildFlameForestForTrack(inWindow, FlameTreeTrack.ui),
    ...buildFlameForestForTrack(inWindow, FlameTreeTrack.dart),
  ];
  dropRedundantDartFrameRoots(roots);
  if (options.treePhases.isNotEmpty) {
    roots = List<SliceTreeNode>.from(_promotePhaseRoots(roots, options.treePhases));
  }

  final coverage = traceCoverageSummary(trace);
  final janky = snapshot.frames.where((f) => f.elapsedMs > budgetMs).toList()
    ..sort((a, b) => b.elapsedUs.compareTo(a.elapsedUs));
  final suggested = slowestTracedJankyFrame(
    jankyFrames: janky,
    trace: trace,
    coverage: coverage,
  );

  String? traceWarning;
  int? suggestedFrame;
  if (flameSlices.isEmpty || !frameHasTraceSlices(frame, trace, coverage)) {
    traceWarning = formatTraceCoverageWarning(
      frame: frame,
      coverage: coverage,
      suggestedFrameNumber: suggested?.number,
    );
    suggestedFrame = suggested?.number;
  }

  if (roots.isEmpty) {
    final markerRange = trace.timeRangeForFrame(frame.number, frame.elapsedUs);
    final windowMs = markerRange != null
        ? (markerRange.endNs - markerRange.beginNs) / 1e6
        : frame.elapsedMs;
    return FlameTreeAnalysis(
      frame: frame,
      budgetMs: budgetMs,
      timelineWindowMs: windowMs,
      roots: roots,
      topSelfTime: const [],
      sliceCountInWindow: flameSlices.length,
      appliedFilters: _flameFiltersMap(options),
      traceCoverageWarning: traceWarning,
      suggestedFrameNumber: suggestedFrame,
    );
  }

  final topSelfTime = collectSelfTimeHotspots(
    roots,
    minSelfMs: options.minSelfMs,
    limit: options.topN,
  );

  pruneSliceTreeMinTotal(roots, options.minSelfMs * 0.5);

  SliceTreeForestOmitted? forestOmitted;
  if (options.treeTopPerLevel > 0) {
    forestOmitted = pruneSliceTreeTopPerLevel(
      roots,
      topK: options.treeTopPerLevel,
      metric: options.treeTopMetric,
    );
  }

  pruneSliceTreeDepth(roots, options.treeDepth);

  final markerRange = trace.timeRangeForFrame(frame.number, frame.elapsedUs);
  final windowMs = markerRange != null
      ? (markerRange.endNs - markerRange.beginNs) / 1e6
      : frame.elapsedMs;

  return FlameTreeAnalysis(
    frame: frame,
    budgetMs: budgetMs,
    timelineWindowMs: windowMs,
    roots: roots,
    topSelfTime: topSelfTime,
    sliceCountInWindow: flameSlices.length,
    appliedFilters: _flameFiltersMap(options),
    forestOmitted: forestOmitted,
    traceCoverageWarning: traceWarning,
    suggestedFrameNumber: suggestedFrame,
  );
}

FlutterFrame? _resolveFlameFrame(
  PerformanceSnapshot snapshot,
  AnalyzeOptions options,
  double budgetMs,
) {
  if (options.frameTarget == FrameTarget.byId && options.frameId != null) {
    return snapshot.frames
        .where((f) => f.number == options.frameId)
        .firstOrNull;
  }
  if (options.frameTarget == FrameTarget.auto ||
      options.format == OutputFormat.flameTree ||
      options.format == OutputFormat.flameTreeJson) {
    final janky = snapshot.frames.where((f) => f.elapsedMs > budgetMs).toList()
      ..sort((a, b) => b.elapsedUs.compareTo(a.elapsedUs));
    if (janky.isNotEmpty) return janky.first;
    if (snapshot.frames.isEmpty) return null;
    return snapshot.frames
        .reduce((a, b) => a.elapsedUs > b.elapsedUs ? a : b);
  }
  return null;
}

Map<String, Object?> _flameFiltersMap(AnalyzeOptions options) {
  return {
    if (options.nameFilter != null) 'nameFilter': options.nameFilter,
    if (options.categories.isNotEmpty) 'categories': options.categories.toList(),
    if (options.excludeEmbedder) 'excludeEmbedder': true,
    if (options.treePhases.isNotEmpty) 'treePhases': options.treePhases.toList(),
    'treeDepth': options.treeDepth,
    'minSelfMs': options.minSelfMs,
    if (options.treeTopPerLevel > 0) 'treeTopPerLevel': options.treeTopPerLevel,
    if (options.treeTopPerLevel > 0) 'treeTopMetric': options.treeTopMetric.name,
  };
}

List<SliceTreeNode> _promotePhaseRoots(
  List<SliceTreeNode> roots,
  Set<String> phases,
) {
  final promoted = <SliceTreeNode>[];
  void walk(SliceTreeNode node) {
    if (_matchesTreePhase(node.slice.name, phases)) {
      promoted.add(node);
      return;
    }
    for (final child in node.children) {
      walk(child);
    }
  }

  for (final root in roots) {
    walk(root);
  }
  promoted.sort((a, b) => b.totalMs.compareTo(a.totalMs));
  return promoted;
}

bool _matchesTreePhase(String name, Set<String> phases) {
  final lower = name.toLowerCase();
  for (final phase in phases) {
    if (lower == phase || lower.startsWith(phase)) return true;
  }
  return false;
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final iterator = this.iterator;
    if (!iterator.moveNext()) return null;
    return iterator.current;
  }
}
