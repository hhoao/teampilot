import 'rebuild_model.dart';

import 'frame_slice_tree.dart';
import 'models.dart';
import 'options.dart';
import 'slice_tree.dart';
import 'trace_decoder.dart';

PrecisionAnalysis? buildPrecisionAnalysis({
  required PerformanceSnapshot snapshot,
  required DecodedTrace trace,
  required AnalyzeOptions options,
  required double budgetMs,
}) {
  final janky = snapshot.frames.where((f) => f.elapsedMs > budgetMs).toList()
    ..sort((a, b) => b.elapsedUs.compareTo(a.elapsedUs));
  if (janky.isEmpty) return null;

  final frameCount = options.precisionFrameCount.clamp(1, janky.length);
  final frames = janky.take(frameCount).toList();
  final filters = options.traceFilters;
  final minSelf = options.minSelfMs;

  final uiPathAgg = <String, _HotPathAccumulator>{};
  final rasterPathAgg = <String, _HotPathAccumulator>{};
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

    _accumulateHotPaths(uiPathAgg, uiHotspots, frame.number, 'ui');
    _accumulateHotPaths(rasterPathAgg, rasterHotspots, frame.number, 'raster');

    final rebuilds = snapshot.rebuildData?.rebuildsByFrame[frame.number] ?? [];
    final matchedSliceKeys = <String>{};

    for (final rebuild in rebuilds) {
      final uiMatches = _matchWidgetToHotspots(rebuild.name, uiHotspots);
      if (uiMatches.isEmpty) {
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
    }

    for (final h in [...uiHotspots, ...rasterHotspots]) {
      final key = '${frame.number}:${h.path}';
      if (matchedSliceKeys.contains(key)) continue;
      if (h.selfMs < minSelf * 2) continue;
      unmatchedSlices.add(
        UnmatchedHighSelfSlice(
          frameNumber: frame.number,
          name: h.name,
          track: h.track.contains('raster') || h.name == rasterEventName
              ? 'raster'
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

  return PrecisionAnalysis(
    frameCountAnalyzed: frames.length,
    rebuildNote: _rebuildNote(snapshot.rebuildData),
    frameGuides: guides,
    uiHotPaths: _finalizeHotPaths(uiPathAgg, options.topN),
    rasterHotPaths: _finalizeHotPaths(rasterPathAgg, options.topN),
    rebuildCorrelations: correlations.take(options.topN).toList(),
    unmatchedHighSelfSlices: unmatchedSlices.take(options.topN).toList(),
    unmatchedHighRebuilds: unmatchedRebuilds.take(options.topN).toList(),
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
          'rebuildCountModel missing — cannot distinguish frequent rebuilds '
          'from expensive single builds. Enable Rebuild Stats in DevTools before export.',
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
