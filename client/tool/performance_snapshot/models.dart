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

class MatchedTimelineSlice {
  const MatchedTimelineSlice({
    required this.name,
    required this.track,
    required this.selfMs,
    required this.totalMs,
    required this.path,
    this.phase,
  });

  final String name;
  final String track;
  final double selfMs;
  final double totalMs;
  final String path;
  final String? phase;
}

class RebuildSliceCorrelation {
  const RebuildSliceCorrelation({
    required this.frameNumber,
    required this.widgetId,
    required this.widgetName,
    this.file,
    this.line,
    this.column,
    required this.rebuildCount,
    required this.matchedSlices,
    required this.matchQuality,
  });

  final int frameNumber;
  final int widgetId;
  final String widgetName;
  final String? file;
  final int? line;
  final int? column;
  final int rebuildCount;
  final List<MatchedTimelineSlice> matchedSlices;
  final String matchQuality;
}

class UnmatchedHighSelfSlice {
  const UnmatchedHighSelfSlice({
    required this.frameNumber,
    required this.name,
    required this.track,
    required this.selfMs,
    required this.path,
    this.phase,
  });

  final int frameNumber;
  final String name;
  final String track;
  final double selfMs;
  final String path;
  final String? phase;
}

class UnmatchedHighRebuild {
  const UnmatchedHighRebuild({
    required this.frameNumber,
    required this.widgetId,
    required this.widgetName,
    this.file,
    this.line,
    this.column,
    required this.rebuildCount,
  });

  final int frameNumber;
  final int widgetId;
  final String widgetName;
  final String? file;
  final int? line;
  final int? column;
  final int rebuildCount;
}

class AggregatedHotPath {
  const AggregatedHotPath({
    required this.path,
    required this.track,
    required this.totalSelfMs,
    required this.maxSelfMsInSingleFrame,
    required this.frameNumbers,
    required this.occurrenceCount,
  });

  final String path;
  final String track;
  final double totalSelfMs;
  final double maxSelfMsInSingleFrame;
  final List<int> frameNumbers;
  final int occurrenceCount;
}

/// Aggregated Dart-track method slice (e.g. `RenderParagraph.getDryLayout`).
class DartMethodHotspot {
  const DartMethodHotspot({
    required this.name,
    required this.renderClass,
    required this.totalMs,
    required this.maxMsInSingleFrame,
    required this.frameNumbers,
    required this.occurrenceCount,
  });

  final String name;
  final String renderClass;
  final double totalMs;
  final double maxMsInSingleFrame;
  final List<int> frameNumbers;
  final int occurrenceCount;
}

class FrameBottleneckGuide {
  const FrameBottleneckGuide({
    required this.frameNumber,
    required this.bottleneck,
    required this.primaryAnalysisTrack,
    required this.buildMs,
    required this.rasterMs,
    required this.elapsedMs,
  });

  final int frameNumber;
  final String bottleneck;
  final String primaryAnalysisTrack;
  final double buildMs;
  final double rasterMs;
  final double elapsedMs;
}

class RebuildPrecisionNote {
  const RebuildPrecisionNote({
    required this.status,
    required this.precisionImpact,
    required this.message,
  });

  final String status;
  final String precisionImpact;
  final String message;
}

class TraceCoverageNote {
  const TraceCoverageNote({
    required this.message,
    required this.jankyFramesWithoutTrace,
    required this.markerFrameFirst,
    required this.markerFrameLast,
    required this.suggestedFrameNumber,
    this.untracedWorstJanky,
    this.precisionFrameNumbers = const [],
    this.precisionExcludesWorstJanky = false,
  });

  final String message;
  final List<int> jankyFramesWithoutTrace;
  final int? markerFrameFirst;
  final int? markerFrameLast;

  /// Slowest janky frame that has timeline slices — optional drill-down only.
  final int? suggestedFrameNumber;

  /// Worst janky frame when it falls outside traceBinary (flutterFrames only).
  final UntracedWorstJankyFrame? untracedWorstJanky;

  /// Frames aggregated into precision hot paths / correlations.
  final List<int> precisionFrameNumbers;

  /// True when [untracedWorstJanky] is the global worst janky frame.
  final bool precisionExcludesWorstJanky;
}

/// flutterFrames timing for a janky frame with no overlapping trace slices.
class UntracedWorstJankyFrame {
  const UntracedWorstJankyFrame({
    required this.frameNumber,
    required this.elapsedMs,
    required this.buildMs,
    required this.rasterMs,
    required this.vsyncMs,
    required this.bottleneck,
    required this.overBudgetMs,
  });

  final int frameNumber;
  final double elapsedMs;
  final double buildMs;
  final double rasterMs;
  final double vsyncMs;
  final String bottleneck;
  final double overBudgetMs;
}

class PrecisionAnalysis {
  const PrecisionAnalysis({
    required this.frameCountAnalyzed,
    required this.rebuildNote,
    required this.frameGuides,
    required this.uiHotPaths,
    required this.rasterHotPaths,
    required this.dartMethodHotspots,
    required this.dartHotPaths,
    required this.rebuildCorrelations,
    required this.unmatchedHighSelfSlices,
    required this.unmatchedHighRebuilds,
    this.traceCoverage,
  });

  final int frameCountAnalyzed;
  final RebuildPrecisionNote rebuildNote;
  final List<FrameBottleneckGuide> frameGuides;
  final List<AggregatedHotPath> uiHotPaths;
  final List<AggregatedHotPath> rasterHotPaths;
  final List<DartMethodHotspot> dartMethodHotspots;
  final List<AggregatedHotPath> dartHotPaths;
  final List<RebuildSliceCorrelation> rebuildCorrelations;
  final List<UnmatchedHighSelfSlice> unmatchedHighSelfSlices;
  final List<UnmatchedHighRebuild> unmatchedHighRebuilds;
  final TraceCoverageNote? traceCoverage;
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
    this.precision,
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
  final PrecisionAnalysis? precision;
}
