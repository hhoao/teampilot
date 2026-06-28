import 'rebuild_model.dart';
import 'trace_decoder.dart';

import 'options.dart';

/// Parsed DevTools performance snapshot (JSON `performance` section + metadata).
class PerformanceSnapshot {
  const PerformanceSnapshot({
    required this.devToolsVersion,
    required this.isDevToolsSnapshot,
    required this.activeScreenId,
    required this.connectedApp,
    required this.displayRefreshRateHz,
    required this.selectedFrameId,
    required this.selectedTab,
    required this.frames,
    required this.rebuildData,
    required this.traceBinary,
  });

  final String? devToolsVersion;
  final bool isDevToolsSnapshot;
  final String? activeScreenId;
  final ConnectedAppInfo? connectedApp;
  final double displayRefreshRateHz;
  final int? selectedFrameId;
  final int? selectedTab;
  final List<FlutterFrame> frames;
  final RebuildCountData? rebuildData;
  final List<int>? traceBinary;

  double budgetMs(AnalyzeOptions options) =>
      options.budgetMsOverride ?? (1000 / displayRefreshRateHz);
}

class ConnectedAppInfo {
  const ConnectedAppInfo({
    required this.flutterVersion,
    required this.operatingSystem,
    required this.isProfileBuild,
    required this.isRunningOnDartVM,
  });

  final String? flutterVersion;
  final String? operatingSystem;
  final bool isProfileBuild;
  final bool isRunningOnDartVM;
}

class FlutterFrame {
  const FlutterFrame({
    required this.number,
    required this.startTimeUs,
    required this.elapsedUs,
    required this.buildUs,
    required this.rasterUs,
    required this.vsyncUs,
  });

  final int number;
  final int startTimeUs;
  final int elapsedUs;
  final int buildUs;
  final int rasterUs;
  final int vsyncUs;

  double get elapsedMs => elapsedUs / 1000;
  double get buildMs => buildUs / 1000;
  double get rasterMs => rasterUs / 1000;
  double get vsyncMs => vsyncUs / 1000;
  int get endTimeUs => startTimeUs + elapsedUs;
}

class TimingStats {
  const TimingStats({
    required this.label,
    required this.minMs,
    required this.p50Ms,
    required this.p95Ms,
    required this.maxMs,
    required this.avgMs,
  });

  final String label;
  final double minMs;
  final double p50Ms;
  final double p95Ms;
  final double maxMs;
  final double avgMs;
}

class JankyFrame {
  const JankyFrame({
    required this.frame,
    required this.bottleneck,
  });

  final FlutterFrame frame;
  final String bottleneck;
}

class FrameSummary {
  const FrameSummary({
    required this.stats,
    required this.jankyFrames,
    required this.jankyCount,
    required this.totalCount,
    required this.budgetMs,
  });

  final List<TimingStats> stats;
  final List<JankyFrame> jankyFrames;
  final int jankyCount;
  final int totalCount;
  final double budgetMs;
}

enum RebuildDataStatus { notCaptured, empty, present }

class RebuildSummary {
  const RebuildSummary({
    required this.status,
    required this.frameCount,
    required this.locationCount,
    required this.topWidgets,
  });

  final RebuildDataStatus status;
  final int frameCount;
  final int locationCount;
  final List<RebuildLocation> topWidgets;
}

class TimelineOverview {
  const TimelineOverview({
    required this.sliceCount,
    required this.instantCount,
    required this.cpuSampleCount,
    required this.trackCount,
    required this.uiFrameMarkerCount,
    required this.rasterFrameMarkerCount,
    required this.uiTrackName,
    required this.rasterTrackName,
  });

  final int sliceCount;
  final int instantCount;
  final int cpuSampleCount;
  final int trackCount;
  final int uiFrameMarkerCount;
  final int rasterFrameMarkerCount;
  final String? uiTrackName;
  final String? rasterTrackName;
}

class RankedSlice {
  const RankedSlice({
    required this.durationMs,
    required this.trackLabel,
    required this.name,
  });

  final double durationMs;
  final String trackLabel;
  final String name;
}

class AggregatedEvent {
  const AggregatedEvent({
    required this.name,
    required this.totalMs,
    required this.maxMs,
    required this.count,
  });

  final String name;
  final double totalMs;
  final double maxMs;
  final int count;
}

class InstantEventSummary {
  const InstantEventSummary({
    required this.totalCount,
    required this.topEvents,
  });

  final int totalCount;
  final List<MapEntry<String, int>> topEvents;
}

class ShaderSummary {
  const ShaderSummary({
    required this.sliceCount,
    required this.instantCount,
    required this.longestSliceMs,
    required this.longestSliceName,
  });

  final int sliceCount;
  final int instantCount;
  final double? longestSliceMs;
  final String? longestSliceName;
}

class CpuSampleSummary {
  const CpuSampleSummary({
    required this.sampleCount,
    required this.topSymbols,
  });

  final int sampleCount;
  final Map<String, int> topSymbols;
}

class FrameDrilldown {
  const FrameDrilldown({
    required this.frame,
    required this.bottleneck,
    required this.timelineWindowMs,
    required this.timelineWindowSource,
    required this.uiBeginMarkerMs,
    required this.rasterMarkerMs,
    required this.rebuilds,
    required this.overlappingSlices,
    required this.dartHotspots,
    required this.frameCpuSymbols,
    required this.dartUiSliceMs,
    required this.rasterSliceMs,
    required this.overBudgetMs,
  });

  final FlutterFrame frame;
  final String bottleneck;
  final double? timelineWindowMs;
  final String timelineWindowSource;
  final double? uiBeginMarkerMs;
  final double? rasterMarkerMs;
  final List<RebuildLocation> rebuilds;
  final List<RankedSlice> overlappingSlices;
  final List<RankedSlice> dartHotspots;
  final Map<String, int> frameCpuSymbols;
  final double dartUiSliceMs;
  final double rasterSliceMs;
  final double? overBudgetMs;
}

class TimelineAnalysis {
  const TimelineAnalysis({
    required this.overview,
    required this.topSlices,
    required this.aggregatedSlices,
    required this.instantSummary,
    required this.shaderSummary,
    required this.cpuSummary,
    required this.trace,
  });

  final TimelineOverview overview;
  final List<RankedSlice> topSlices;
  final List<AggregatedEvent> aggregatedSlices;
  final InstantEventSummary? instantSummary;
  final ShaderSummary? shaderSummary;
  final CpuSampleSummary? cpuSummary;
  final DecodedTrace trace;
}

class SnapshotComparison {
  const SnapshotComparison({
    required this.baselineLabel,
    required this.candidateLabel,
    required this.jankyCountBaseline,
    required this.jankyCountCandidate,
    required this.worstFrameMsBaseline,
    required this.worstFrameMsCandidate,
    required this.avgFrameMsBaseline,
    required this.avgFrameMsCandidate,
    required this.topSliceRegressions,
  });

  final String baselineLabel;
  final String candidateLabel;
  final int jankyCountBaseline;
  final int jankyCountCandidate;
  final double worstFrameMsBaseline;
  final double worstFrameMsCandidate;
  final double avgFrameMsBaseline;
  final double avgFrameMsCandidate;
  final List<SliceRegression> topSliceRegressions;
}

class SliceRegression {
  const SliceRegression({
    required this.name,
    required this.maxMsBaseline,
    required this.maxMsCandidate,
    required this.deltaMs,
  });

  final String name;
  final double maxMsBaseline;
  final double maxMsCandidate;
  final double deltaMs;
}

class PerformanceAnalysisResult {
  const PerformanceAnalysisResult({
    required this.snapshot,
    required this.budgetMs,
    required this.exportedTabLabel,
    required this.traceBinaryKiB,
    required this.rebuildStatus,
    required this.frameSummary,
    required this.rebuildSummary,
    required this.timeline,
    required this.frameDrilldown,
    required this.worstFrameDrilldowns,
    required this.comparison,
    required this.missingFrameId,
    required this.slowestFrameTip,
    required this.appliedFilters,
  });

  final PerformanceSnapshot snapshot;
  final double budgetMs;
  final String? exportedTabLabel;
  final double? traceBinaryKiB;
  final RebuildDataStatus rebuildStatus;
  final FrameSummary? frameSummary;
  final RebuildSummary rebuildSummary;
  final TimelineAnalysis? timeline;
  final FrameDrilldown? frameDrilldown;
  final List<FrameDrilldown> worstFrameDrilldowns;
  final SnapshotComparison? comparison;
  final int? missingFrameId;
  final int? slowestFrameTip;
  final Map<String, Object?> appliedFilters;
}
