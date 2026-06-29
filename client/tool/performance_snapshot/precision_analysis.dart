import 'dart_slice_analysis.dart';
import 'rebuild_model.dart';

import 'frame_slice_tree.dart';
import 'models.dart';
import 'options.dart';
import 'slice_tree.dart';
import 'trace_decoder.dart';
import 'trace_frame_coverage.dart';

PrecisionAnalysis? buildPrecisionAnalysis({
  required PerformanceSnapshot snapshot,
  required DecodedTrace trace,
  required AnalyzeOptions options,
  required double budgetMs,
}) {
  final janky = snapshot.frames.where((f) => f.elapsedMs > budgetMs).toList()
    ..sort((a, b) => b.elapsedUs.compareTo(a.elapsedUs));
  if (janky.isEmpty) return null;

  final coverage = traceCoverageSummary(trace);
  final tracedJanky = tracedJankyFrames(
    jankyFrames: janky,
    trace: trace,
    coverage: coverage,
  );

  final suggested = slowestTracedJankyFrame(
    jankyFrames: janky,
    trace: trace,
    coverage: coverage,
  );

  if (tracedJanky.isEmpty) {
    return PrecisionAnalysis(
      frameCountAnalyzed: 0,
      rebuildNote: _rebuildNote(snapshot.rebuildData),
      frameGuides: const [],
      uiHotPaths: const [],
      rasterHotPaths: const [],
      dartMethodHotspots: const [],
      dartHotPaths: const [],
      rebuildCorrelations: const [],
      unmatchedHighSelfSlices: const [],
      unmatchedHighRebuilds: const [],
      traceCoverage: _buildTraceCoverageNote(
        janky: janky,
        tracedJanky: tracedJanky,
        precisionFrames: const [],
        coverage: coverage,
        budgetMs: budgetMs,
        suggested: suggested,
      ),
    );
  }

  final frameCount =
      options.precisionFrameCount.clamp(1, tracedJanky.length);
  final frames = tracedJanky.take(frameCount).toList();

  final traceCoverageNote = _buildTraceCoverageNote(
    janky: janky,
    tracedJanky: tracedJanky,
    precisionFrames: frames,
    coverage: coverage,
    budgetMs: budgetMs,
    suggested: suggested,
  );
  final filters = options.traceFilters;
  final minSelf = options.minSelfMs;

  final uiPathAgg = <String, _HotPathAccumulator>{};
  final rasterPathAgg = <String, _HotPathAccumulator>{};
  final dartPathAgg = <String, _HotPathAccumulator>{};
  final dartMethodAgg = <String, DartMethodAccumulator>{};
  final correlations = <RebuildSliceCorrelation>[];
  final unmatchedSlices = <UnmatchedHighSelfSlice>[];
  final unmatchedRebuilds = <UnmatchedHighRebuild>[];
  final guides = <FrameBottleneckGuide>[];

  for (final frame in frames) {
    guides.add(
      FrameBottleneckGuide(
        frameNumber: frame.number,
        bottleneck: frameBottleneck(frame),
        primaryAnalysisTrack: primaryAnalysisTrack(frame),
        buildMs: frame.buildMs,
        rasterMs: frame.rasterMs,
        elapsedMs: frame.elapsedMs,
      ),
    );

    final uiHotspots = collectFrameSelfTimeHotspots(
      trace: trace,
      frame: frame,
      filters: filters,
      track: FlameTreeTrack.ui,
      minSelfMs: minSelf,
      limit: options.topN,
    );
    final rasterHotspots = collectFrameSelfTimeHotspots(
      trace: trace,
      frame: frame,
      filters: filters,
      track: FlameTreeTrack.raster,
      minSelfMs: minSelf,
      limit: options.topN,
    );
    final dartHotspots = collectFrameSelfTimeHotspots(
      trace: trace,
      frame: frame,
      filters: filters,
      track: FlameTreeTrack.dart,
      minSelfMs: minSelf,
      limit: options.topN,
    );

    final inWindow = slicesInFrameWindow(
      trace: trace,
      frame: frame,
      filters: filters,
    );
    accumulateDartMethodSlices(
      dartMethodAgg,
      inWindow,
      frame.number,
      minMs: minSelf,
    );

    _accumulateHotPaths(uiPathAgg, uiHotspots, frame.number, 'ui');
    _accumulateHotPaths(rasterPathAgg, rasterHotspots, frame.number, 'raster');
    _accumulateHotPaths(dartPathAgg, dartHotspots, frame.number, 'dart');

    final rebuilds = snapshot.rebuildData?.rebuildsByFrame[frame.number] ?? [];
    final matchedSliceKeys = <String>{};

    for (final rebuild in rebuilds) {
      final uiMatches = _matchWidgetToHotspots(rebuild.name, uiHotspots);
      final dartMatches = uiMatches.isEmpty
          ? _matchWidgetToDartSlices(rebuild.name, inWindow)
          : const <TraceSlice>[];

      if (uiMatches.isEmpty && dartMatches.isEmpty) {
        if (rebuild.buildCount >= 2) {
          unmatchedRebuilds.add(
            UnmatchedHighRebuild(
              frameNumber: frame.number,
              widgetId: rebuild.id,
              widgetName: rebuild.name,
              file: rebuild.file,
              line: rebuild.line,
              column: rebuild.column,
              rebuildCount: rebuild.buildCount,
            ),
          );
        }
        continue;
      }

      if (uiMatches.isNotEmpty) {
        final quality = _matchQuality(rebuild.name, uiMatches);
        final matched = [
          for (final h in uiMatches)
            MatchedTimelineSlice(
              name: h.name,
              track: h.track,
              selfMs: h.selfMs,
              totalMs: h.totalMs,
              path: h.path,
              phase: inferPhaseFromPath(h.path),
            ),
        ];
        for (final h in uiMatches) {
          matchedSliceKeys.add('${frame.number}:${h.path}');
        }

        correlations.add(
          RebuildSliceCorrelation(
            frameNumber: frame.number,
            widgetId: rebuild.id,
            widgetName: rebuild.name,
            file: rebuild.file,
            line: rebuild.line,
            column: rebuild.column,
            rebuildCount: rebuild.buildCount,
            matchedSlices: matched,
            matchQuality: quality,
          ),
        );
        continue;
      }

      final matched = [
        for (final s in dartMatches)
          MatchedTimelineSlice(
            name: s.name,
            track: 'dart',
            selfMs: s.durationMs,
            totalMs: s.durationMs,
            path: s.name,
          ),
      ];
      for (final s in dartMatches) {
        matchedSliceKeys.add('${frame.number}:dart:${s.name}');
      }

      correlations.add(
        RebuildSliceCorrelation(
          frameNumber: frame.number,
          widgetId: rebuild.id,
          widgetName: rebuild.name,
          file: rebuild.file,
          line: rebuild.line,
          column: rebuild.column,
          rebuildCount: rebuild.buildCount,
          matchedSlices: matched,
          matchQuality: _dartMatchQuality(rebuild.name, dartMatches),
        ),
      );
    }

    for (final h in [...uiHotspots, ...rasterHotspots, ...dartHotspots]) {
      final key = '${frame.number}:${h.path}';
      if (matchedSliceKeys.contains(key)) continue;
      if (h.selfMs < minSelf * 2) continue;
      unmatchedSlices.add(
        UnmatchedHighSelfSlice(
          frameNumber: frame.number,
          name: h.name,
          track: h.track.contains('raster') || h.name == rasterEventName
              ? 'raster'
              : isDartMethodSliceByName(h.name)
                  ? 'dart'
                  : 'ui',
          selfMs: h.selfMs,
          path: h.path,
          phase: inferPhaseFromPath(h.path),
        ),
      );
    }
  }

  correlations.sort((a, b) {
    final aSelf = a.matchedSlices.fold<double>(0, (s, m) => s + m.selfMs);
    final bSelf = b.matchedSlices.fold<double>(0, (s, m) => s + m.selfMs);
    final bySelf = bSelf.compareTo(aSelf);
    if (bySelf != 0) return bySelf;
    return b.rebuildCount.compareTo(a.rebuildCount);
  });

  unmatchedSlices.sort((a, b) => b.selfMs.compareTo(a.selfMs));
  unmatchedRebuilds.sort((a, b) => b.rebuildCount.compareTo(a.rebuildCount));

  final orderedGuides = _orderedFrameGuides(
    guides: guides,
    traceCoverage: traceCoverageNote,
  );

  return PrecisionAnalysis(
    frameCountAnalyzed: frames.length,
    rebuildNote: _rebuildNote(snapshot.rebuildData),
    frameGuides: orderedGuides,
    uiHotPaths: _finalizeHotPaths(uiPathAgg, options.topN),
    rasterHotPaths: _finalizeHotPaths(rasterPathAgg, options.topN),
    dartMethodHotspots:
        aggregateDartMethodHotspots(agg: dartMethodAgg, limit: options.topN),
    dartHotPaths: _finalizeHotPaths(dartPathAgg, options.topN),
    rebuildCorrelations: correlations.take(options.topN).toList(),
    unmatchedHighSelfSlices: unmatchedSlices.take(options.topN).toList(),
    unmatchedHighRebuilds: unmatchedRebuilds.take(options.topN).toList(),
    traceCoverage: traceCoverageNote,
  );
}

class _HotPathAccumulator {
  double totalSelfMs = 0;
  double maxSelfMs = 0;
  final frameNumbers = <int>[];
}

void _accumulateHotPaths(
  Map<String, _HotPathAccumulator> agg,
  List<SliceSelfTimeEntry> hotspots,
  int frameNumber,
  String track,
) {
  for (final h in hotspots) {
    final key = '$track:${h.path}';
    final bucket = agg.putIfAbsent(key, _HotPathAccumulator.new);
    bucket.totalSelfMs += h.selfMs;
    bucket.maxSelfMs = bucket.maxSelfMs < h.selfMs ? h.selfMs : bucket.maxSelfMs;
    if (!bucket.frameNumbers.contains(frameNumber)) {
      bucket.frameNumbers.add(frameNumber);
    }
  }
}

List<AggregatedHotPath> _finalizeHotPaths(
  Map<String, _HotPathAccumulator> agg,
  int limit,
) {
  final entries = agg.entries.toList()
    ..sort((a, b) => b.value.totalSelfMs.compareTo(a.value.totalSelfMs));

  return [
    for (final e in entries.take(limit))
      AggregatedHotPath(
        path: e.key.split(':').skip(1).join(':'),
        track: e.key.split(':').first,
        totalSelfMs: e.value.totalSelfMs,
        maxSelfMsInSingleFrame: e.value.maxSelfMs,
        frameNumbers: [...e.value.frameNumbers]..sort(),
        occurrenceCount: e.value.frameNumbers.length,
      ),
  ];
}

RebuildPrecisionNote _rebuildNote(RebuildCountData? data) {
  if (data == null) {
    return const RebuildPrecisionNote(
      status: 'notCaptured',
      precisionImpact: 'high',
      message:
          'rebuildCountModel missing in export — rebuild ↔ slice correlation '
          'unavailable.',
    );
  }
  if (data.isEmpty) {
    return const RebuildPrecisionNote(
      status: 'empty',
      precisionImpact: 'medium',
      message: 'rebuildCountModel present but no rebuild events recorded.',
    );
  }
  return const RebuildPrecisionNote(
    status: 'present',
    precisionImpact: 'low',
    message: 'rebuildCountModel available for rebuild ↔ slice correlation.',
  );
}

List<SliceSelfTimeEntry> _matchWidgetToHotspots(
  String widgetName,
  List<SliceSelfTimeEntry> hotspots,
) {
  return [
    for (final h in hotspots)
      if (widgetMatchesSliceName(widgetName, h.name)) h,
  ];
}

List<TraceSlice> _matchWidgetToDartSlices(
  String widgetName,
  List<TraceSlice> inWindow,
) {
  return [
    for (final s in dartMethodSlicesInWindow(inWindow))
      if (widgetMatchesDartMethodSlice(widgetName, s.name)) s,
  ];
}

String _dartMatchQuality(String widgetName, List<TraceSlice> matches) {
  final normalized = normalizeWidgetName(widgetName);
  for (final m in matches) {
    if (m.name.startsWith('Render$normalized') ||
        m.name.startsWith('_Render$normalized')) {
      return 'strong';
    }
    if (widgetMatchesDartMethodSlice(widgetName, m.name)) {
      const textWidgets = {'Text', 'RichText', 'SelectableText'};
      if (textWidgets.contains(normalized) &&
          m.name.contains('Paragraph')) {
        return 'weak';
      }
      return 'strong';
    }
  }
  return 'weak';
}

bool isDartMethodSliceByName(String name) =>
    name.startsWith('Render') || name.startsWith('_Render');

TraceCoverageNote? _buildTraceCoverageNote({
  required List<FlutterFrame> janky,
  required List<FlutterFrame> tracedJanky,
  required List<FlutterFrame> precisionFrames,
  required TraceCoverageSummary coverage,
  required double budgetMs,
  required FlutterFrame? suggested,
}) {
  final skippedNoTrace = [
    for (final frame in janky)
      if (!tracedJanky.any((t) => t.number == frame.number)) frame.number,
  ];
  if (skippedNoTrace.isEmpty) return null;

  final worstSkipped = janky.firstWhere(
    (f) => skippedNoTrace.contains(f.number),
  );
  final worstOverall = janky.first;
  final precisionExcludesWorst =
      !tracedJanky.any((t) => t.number == worstOverall.number);
  final precisionFrameNumbers = [
    for (final frame in precisionFrames) frame.number,
  ];

  UntracedWorstJankyFrame? untracedWorst;
  if (precisionExcludesWorst) {
    untracedWorst = UntracedWorstJankyFrame(
      frameNumber: worstOverall.number,
      elapsedMs: worstOverall.elapsedMs,
      buildMs: worstOverall.buildMs,
      rasterMs: worstOverall.rasterMs,
      vsyncMs: worstOverall.vsyncMs,
      bottleneck: frameBottleneck(worstOverall),
      overBudgetMs: worstOverall.elapsedMs - budgetMs,
    );
  }

  return TraceCoverageNote(
    message: formatTraceCoverageWarning(
      frame: worstSkipped,
      coverage: coverage,
      suggestedFrameNumber: suggested?.number,
      precisionFrameNumbers: precisionFrameNumbers,
    ),
    jankyFramesWithoutTrace: skippedNoTrace,
    markerFrameFirst: coverage.firstMarkerFrame,
    markerFrameLast: coverage.lastMarkerFrame,
    suggestedFrameNumber: suggested?.number,
    untracedWorstJanky: untracedWorst,
    precisionFrameNumbers: precisionFrameNumbers,
    precisionExcludesWorstJanky: precisionExcludesWorst,
  );
}

List<FrameBottleneckGuide> _orderedFrameGuides({
  required List<FrameBottleneckGuide> guides,
  required TraceCoverageNote? traceCoverage,
}) {
  final untraced = traceCoverage?.untracedWorstJanky;
  if (untraced == null) return guides;

  final primary = FrameBottleneckGuide(
    frameNumber: untraced.frameNumber,
    bottleneck: untraced.bottleneck,
    primaryAnalysisTrack: 'flutterFrames-only',
    buildMs: untraced.buildMs,
    rasterMs: untraced.rasterMs,
    elapsedMs: untraced.elapsedMs,
  );
  return [primary, ...guides];
}

String _matchQuality(String widgetName, List<SliceSelfTimeEntry> matches) {
  final normalized = normalizeWidgetName(widgetName);
  for (final m in matches) {
    if (m.name == widgetName || m.name == normalized) return 'strong';
    if (m.name.contains(normalized)) return 'strong';
  }
  return 'weak';
}

/// Strips generic type args: `BlocProvider<Foo>` → `BlocProvider`.
String normalizeWidgetName(String name) {
  final lt = name.indexOf('<');
  if (lt > 0) return name.substring(0, lt);
  return name;
}

bool widgetMatchesSliceName(String widgetName, String sliceName) {
  final base = normalizeWidgetName(widgetName);
  if (sliceName == widgetName || sliceName == base) return true;
  if (sliceName.contains(base) && base.length >= 4) return true;
  if (base.contains(sliceName) && sliceName.length >= 6) return true;

  if (sliceName.startsWith('Render')) {
    final renderTail = sliceName.substring(6);
    if (renderTail.contains(base) || base.contains(renderTail)) return true;
  }

  final widgetTail = base.split('.').last;
  if (widgetTail.length >= 4 && sliceName.contains(widgetTail)) return true;

  return false;
}
