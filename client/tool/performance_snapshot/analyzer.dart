import 'dart:math' as math;

import 'models.dart';
import 'options.dart';
import 'precision_analysis.dart';
import 'rebuild_model.dart';
import 'frame_slice_tree.dart';
import 'snapshot_loader.dart';
import 'trace_decoder.dart';
import 'trace_filters.dart';

/// Runs all performance analysis on a loaded snapshot.
PerformanceAnalysisResult analyzeSnapshot(
  PerformanceSnapshot snapshot,
  AnalyzeOptions options, {
  String snapshotLabel = 'snapshot',
}) {
  final budgetMs = snapshot.budgetMs(options);
  final rebuildRawStatus = snapshot.rebuildData == null
      ? RebuildDataStatus.notCaptured
      : snapshot.rebuildData!.isEmpty
          ? RebuildDataStatus.empty
          : RebuildDataStatus.present;

  final traceKiB = snapshot.traceBinary != null
      ? snapshot.traceBinary!.length / 1024
      : null;

  FrameSummary? frameSummary;
  if (snapshot.frames.isNotEmpty && options.includes(ReportSection.frames)) {
    frameSummary = _analyzeFrames(snapshot.frames, budgetMs, options.jankyOnly);
  }

  final rebuildSummary = options.includes(ReportSection.rebuild)
      ? _analyzeRebuilds(snapshot.rebuildData, options.topN)
      : const RebuildSummary(
          status: RebuildDataStatus.notCaptured,
          frameCount: 0,
          locationCount: 0,
          topWidgets: [],
        );

  TimelineAnalysis? timeline;
  if (snapshot.traceBinary != null && options.needsTimeline) {
    timeline = _analyzeTimeline(
      snapshot.traceBinary!,
      options.topN,
      options.traceFilters,
    );
  }

  final resolvedFrameId = _resolveFrameId(snapshot, options, frameSummary);
  FrameDrilldown? drilldown;
  int? missingFrameId;
  int? slowestTip;

  final worstDrilldowns = <FrameDrilldown>[];
  if (timeline != null && options.includes(ReportSection.drilldown)) {
    if (options.worstFrames > 0) {
      final janky = snapshot.frames
          .where((f) => f.elapsedMs > budgetMs)
          .toList()
        ..sort((a, b) => b.elapsedMs.compareTo(a.elapsedMs));
      for (final frame in janky.take(options.worstFrames)) {
        worstDrilldowns.add(
          _analyzeFrameDrilldown(
            frame: frame,
            trace: timeline.trace,
            rebuildData: snapshot.rebuildData,
            budgetMs: budgetMs,
            filters: options.traceFilters,
          ),
        );
      }
    }

    if (resolvedFrameId != null &&
        (options.worstFrames == 0 || options.frameTarget == FrameTarget.byId)) {
      final frame =
          snapshot.frames.where((f) => f.number == resolvedFrameId).firstOrNull;
      if (frame != null) {
        drilldown = _analyzeFrameDrilldown(
          frame: frame,
          trace: timeline.trace,
          rebuildData: snapshot.rebuildData,
          budgetMs: budgetMs,
          filters: options.traceFilters,
        );
      } else {
        missingFrameId = resolvedFrameId;
      }
    } else if (options.frameTarget == FrameTarget.none &&
        options.worstFrames == 0 &&
        snapshot.frames.isNotEmpty) {
      slowestTip = snapshot.frames
          .reduce((a, b) => a.elapsedUs > b.elapsedUs ? a : b)
          .number;
    }
  }

  PrecisionAnalysis? precision;
  if (timeline != null && options.includes(ReportSection.precision)) {
    precision = buildPrecisionAnalysis(
      snapshot: snapshot,
      trace: timeline.trace,
      options: options,
      budgetMs: budgetMs,
    );
  }

  SnapshotComparison? comparison;
  if (options.comparePath != null && options.includes(ReportSection.compare)) {
    comparison = _compareSnapshots(
      baselinePath: options.comparePath!,
      candidate: snapshot,
      candidateResult: PerformanceAnalysisResult(
        snapshot: snapshot,
        budgetMs: budgetMs,
        exportedTabLabel: tabLabel(snapshot.selectedTab),
        traceBinaryKiB: traceKiB,
        rebuildStatus: rebuildRawStatus,
        frameSummary: frameSummary,
        rebuildSummary: rebuildSummary,
        timeline: timeline,
        frameDrilldown: drilldown,
        worstFrameDrilldowns: worstDrilldowns,
        comparison: null,
        missingFrameId: missingFrameId,
        slowestFrameTip: slowestTip,
        appliedFilters: _appliedFiltersMap(options),
        precision: precision,
      ),
      options: options,
      candidateLabel: snapshotLabel,
    );
  }

  return PerformanceAnalysisResult(
    snapshot: snapshot,
    budgetMs: budgetMs,
    exportedTabLabel: tabLabel(snapshot.selectedTab),
    traceBinaryKiB: traceKiB,
    rebuildStatus: rebuildRawStatus,
    frameSummary: frameSummary,
    rebuildSummary: rebuildSummary,
    timeline: timeline,
    frameDrilldown: drilldown,
    worstFrameDrilldowns: worstDrilldowns,
    comparison: comparison,
    missingFrameId: missingFrameId,
    slowestFrameTip: slowestTip,
    appliedFilters: _appliedFiltersMap(options),
    precision: precision,
  );
}

Map<String, Object?> _appliedFiltersMap(AnalyzeOptions options) => {
      if (options.nameFilter != null) 'nameFilter': options.nameFilter,
      if (options.categories.isNotEmpty) 'categories': options.categories.toList(),
      if (options.excludeEmbedder) 'excludeEmbedder': true,
      if (options.jankyOnly) 'jankyOnly': true,
    };

int? _resolveFrameId(
  PerformanceSnapshot snapshot,
  AnalyzeOptions options,
  FrameSummary? frameSummary,
) {
  switch (options.frameTarget) {
    case FrameTarget.byId:
      return options.frameId;
    case FrameTarget.auto:
      if (snapshot.frames.isEmpty) return null;
      final budget = snapshot.budgetMs(options);
      final janky = snapshot.frames.where((f) => f.elapsedMs > budget).toList()
        ..sort((a, b) => b.elapsedMs.compareTo(a.elapsedMs));
      if (janky.isNotEmpty) return janky.first.number;
      return snapshot.frames
          .reduce((a, b) => a.elapsedUs > b.elapsedUs ? a : b)
          .number;
    case FrameTarget.none:
      return snapshot.selectedFrameId;
  }
}

FrameSummary _analyzeFrames(
  List<FlutterFrame> frames,
  double budgetMs,
  bool jankyOnly,
) {
  final elapsed = frames.map((f) => f.elapsedMs).toList()..sort();
  final build = frames.map((f) => f.buildMs).toList()..sort();
  final raster = frames.map((f) => f.rasterMs).toList()..sort();

  final janky = frames.where((f) => f.elapsedMs > budgetMs).toList()
    ..sort((a, b) => b.elapsedMs.compareTo(a.elapsedMs));

  return FrameSummary(
    stats: jankyOnly
        ? const []
        : [
            _timingStats('Frame total', elapsed),
            _timingStats('  Build', build),
            _timingStats('  Raster', raster),
          ],
    jankyFrames: [
      for (final f in janky.take(8))
        JankyFrame(frame: f, bottleneck: frameBottleneck(f)),
    ],
    jankyCount: janky.length,
    totalCount: frames.length,
    budgetMs: budgetMs,
  );
}

TimingStats _timingStats(String label, List<double> sorted) {
  if (sorted.isEmpty) {
    return TimingStats(
      label: label,
      minMs: 0,
      p50Ms: 0,
      p95Ms: 0,
      maxMs: 0,
      avgMs: 0,
    );
  }
  final n = sorted.length;
  double pct(double p) => sorted[math.min(n - 1, (n * p).floor())];
  final sum = sorted.reduce((a, b) => a + b);
  return TimingStats(
    label: label,
    minMs: sorted.first,
    p50Ms: pct(0.5),
    p95Ms: pct(0.95),
    maxMs: sorted.last,
    avgMs: sum / n,
  );
}

RebuildSummary _analyzeRebuilds(RebuildCountData? data, int topN) {
  if (data == null || data.isEmpty) {
    return RebuildSummary(
      status: data == null
          ? RebuildDataStatus.notCaptured
          : RebuildDataStatus.empty,
      frameCount: 0,
      locationCount: data?.locationsById.length ?? 0,
      topWidgets: const [],
    );
  }
  return RebuildSummary(
    status: RebuildDataStatus.present,
    frameCount: data.rebuildsByFrame.length,
    locationCount: data.locationsById.length,
    topWidgets: data.topOverall(limit: topN),
  );
}

TimelineAnalysis _analyzeTimeline(
  List<int> bytes,
  int topN,
  TraceFilters filters,
) {
  final trace = decodeTrace(bytes);
  final filteredSlices = filters.applySlices(trace.slices);
  final filteredInstants =
      filters.isActive ? trace.instants.where(filters.matchesInstant).toList() : trace.instants;

  final ranked = List<TraceSlice>.from(filteredSlices)
    ..sort((a, b) => b.durationNs.compareTo(a.durationNs));

  final topSlices = [
    for (final s in ranked.take(topN))
      RankedSlice(
        durationMs: s.durationMs,
        trackLabel: s.trackLabel,
        name: s.name,
      ),
  ];

  final aggregated = [
    for (final e in aggregateSlices(filteredSlices).take(topN))
      AggregatedEvent(
        name: e.key,
        totalMs: e.value.totalNs / 1e6,
        maxMs: e.value.maxNs / 1e6,
        count: e.value.count,
      ),
  ];

  InstantEventSummary? instantSummary;
  if (filteredInstants.isNotEmpty) {
    final counts = <String, int>{};
    for (final event in filteredInstants) {
      final key = event.category.isEmpty
          ? event.name
          : '${event.category}::${event.name}';
      counts[key] = (counts[key] ?? 0) + 1;
    }
    final rankedInstants = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    instantSummary = InstantEventSummary(
      totalCount: filteredInstants.length,
      topEvents: rankedInstants.take(topN).toList(),
    );
  }

  ShaderSummary? shaderSummary;
  final shaderSlices = filteredSlices.where((s) => s.isShaderEvent).toList();
  final shaderInstants =
      filteredInstants.where((e) => e.isShaderEvent).toList();
  if (shaderSlices.isNotEmpty || shaderInstants.isNotEmpty) {
    shaderSlices.sort((a, b) => b.durationNs.compareTo(a.durationNs));
    shaderSummary = ShaderSummary(
      sliceCount: shaderSlices.length,
      instantCount: shaderInstants.length,
      longestSliceMs:
          shaderSlices.isEmpty ? null : shaderSlices.first.durationMs,
      longestSliceName: shaderSlices.isEmpty ? null : shaderSlices.first.name,
    );
  }

  CpuSampleSummary? cpuSummary;
  if (trace.cpuSamples.isNotEmpty) {
    cpuSummary = CpuSampleSummary(
      sampleCount: trace.cpuSamples.length,
      topSymbols: topCpuSymbols(trace.cpuSamples, limit: topN),
    );
  }

  return TimelineAnalysis(
    overview: TimelineOverview(
      sliceCount: filteredSlices.length,
      instantCount: filteredInstants.length,
      cpuSampleCount: trace.cpuSamples.length,
      trackCount: trace.tracks.length,
      uiFrameMarkerCount: trace.uiFrameBeginNs.length,
      rasterFrameMarkerCount: trace.rasterFrameBeginNs.length,
      uiTrackName: trace.uiTrackUuid != null
          ? trace.tracks[trace.uiTrackUuid]
          : null,
      rasterTrackName: trace.rasterTrackUuid != null
          ? trace.tracks[trace.rasterTrackUuid]
          : null,
    ),
    topSlices: topSlices,
    aggregatedSlices: aggregated,
    instantSummary: instantSummary,
    shaderSummary: shaderSummary,
    cpuSummary: cpuSummary,
    trace: trace,
  );
}

FrameDrilldown _analyzeFrameDrilldown({
  required FlutterFrame frame,
  required DecodedTrace trace,
  required RebuildCountData? rebuildData,
  required double budgetMs,
  required TraceFilters filters,
}) {
  final markerRange = trace.timeRangeForFrame(frame.number, frame.elapsedUs);
  final timelineWindowMs = markerRange != null
      ? (markerRange.endNs - markerRange.beginNs) / 1e6
      : null;
  final timelineWindowSource = markerRange != null
      ? markerRange.source
      : 'flutterFrames fallback';

  final uiMarker = trace.uiFrameBeginNs[frame.number];
  final rasterMarker = trace.rasterFrameBeginNs[frame.number];

  final rebuilds = rebuildData?.rebuildsByFrame[frame.number] ?? const [];
  final sortedRebuilds = [...rebuilds]
    ..sort((a, b) => b.buildCount.compareTo(a.buildCount));

  final inWindow = filters.applySlices(
    slicesForFrame(
      trace: trace,
      frameNumber: frame.number,
      startTimeUs: frame.startTimeUs,
      elapsedUs: frame.elapsedUs,
    ),
  );

  final dartHotspots = inWindow
      .where((s) => s.category == 'Dart')
      .where((s) => isInterestingDartEvent(s.name))
      .take(15)
      .map(
        (s) => RankedSlice(
          durationMs: s.durationMs,
          trackLabel: s.trackLabel,
          name: s.name,
        ),
      )
      .toList();

  final frameCpu = trace.cpuSamples.where((sample) {
    if (markerRange == null) return false;
    return sample.timestampNs >= markerRange.beginNs &&
        sample.timestampNs <= markerRange.endNs;
  }).toList();

  final uiNs = inWindow
      .where((s) => s.track.contains('.ui') || s.category == 'Dart')
      .fold<int>(0, (sum, s) => sum + s.durationNs);
  final rasterNs = inWindow
      .where(
        (s) =>
            s.track.contains('.raster') ||
            s.track.contains('.platform') ||
            s.name == rasterEventName,
      )
      .fold<int>(0, (sum, s) => sum + s.durationNs);

  return FrameDrilldown(
    frame: frame,
    bottleneck: frameBottleneck(frame),
    timelineWindowMs: timelineWindowMs,
    timelineWindowSource: timelineWindowSource,
    uiBeginMarkerMs: uiMarker != null ? uiMarker / 1e6 : null,
    rasterMarkerMs: rasterMarker != null ? rasterMarker / 1e6 : null,
    rebuilds: sortedRebuilds.take(15).toList(),
    overlappingSlices: [
      for (final s in inWindow.take(40))
        RankedSlice(
          durationMs: s.durationMs,
          trackLabel: s.trackLabel,
          name: s.name,
        ),
    ],
    dartHotspots: dartHotspots,
    frameCpuSymbols: frameCpu.isEmpty
        ? const {}
        : topCpuSymbols(frameCpu, limit: 10),
    dartUiSliceMs: uiNs / 1e6,
    rasterSliceMs: rasterNs / 1e6,
    overBudgetMs:
        frame.elapsedMs > budgetMs ? frame.elapsedMs - budgetMs : null,
  );
}

SnapshotComparison _compareSnapshots({
  required String baselinePath,
  required PerformanceSnapshot candidate,
  required PerformanceAnalysisResult candidateResult,
  required AnalyzeOptions options,
  required String candidateLabel,
}) {
  final baseline = loadSnapshotFromFile(baselinePath);
  final baselineResult = analyzeSnapshot(
    baseline,
    AnalyzeOptions(
      frameTarget: options.frameTarget,
      frameId: options.frameId,
      topN: options.topN,
      budgetMsOverride: options.budgetMsOverride,
      sections: {
        ReportSection.frames,
        ReportSection.timeline,
      },
      nameFilter: options.nameFilter,
      categories: options.categories,
      excludeEmbedder: options.excludeEmbedder,
    ),
    snapshotLabel: baselinePath,
  );

  final baselineFrames = baseline.frames;
  final candidateFrames = candidate.frames;

  double worstMs(List<FlutterFrame> frames) => frames.isEmpty
      ? 0
      : frames.map((f) => f.elapsedMs).reduce(math.max);

  double avgMs(List<FlutterFrame> frames) => frames.isEmpty
      ? 0
      : frames.map((f) => f.elapsedMs).reduce((a, b) => a + b) / frames.length;

  final baselineAgg = {
    for (final e in baselineResult.timeline?.aggregatedSlices ?? [])
      e.name: e.maxMs,
  };
  final candidateAgg = {
    for (final e in candidateResult.timeline?.aggregatedSlices ?? [])
      e.name: e.maxMs,
  };

  final regressions = <SliceRegression>[];
  for (final entry in candidateAgg.entries) {
    final baselineMax = baselineAgg[entry.key] ?? 0;
    final delta = entry.value - baselineMax;
    if (delta > 0.5) {
      regressions.add(
        SliceRegression(
          name: entry.key,
          maxMsBaseline: baselineMax,
          maxMsCandidate: entry.value,
          deltaMs: delta,
        ),
      );
    }
  }
  regressions.sort((a, b) => b.deltaMs.compareTo(a.deltaMs));

  return SnapshotComparison(
    baselineLabel: baselinePath,
    candidateLabel: candidateLabel,
    jankyCountBaseline: baselineResult.frameSummary?.jankyCount ?? 0,
    jankyCountCandidate: candidateResult.frameSummary?.jankyCount ?? 0,
    worstFrameMsBaseline: worstMs(baselineFrames),
    worstFrameMsCandidate: worstMs(candidateFrames),
    avgFrameMsBaseline: avgMs(baselineFrames),
    avgFrameMsCandidate: avgMs(candidateFrames),
    topSliceRegressions: regressions.take(options.topN).toList(),
  );
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    if (!it.moveNext()) return null;
    return it.current;
  }
}
