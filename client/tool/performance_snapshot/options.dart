import 'trace_filters.dart';

import 'slice_tree.dart';

/// Output format for CLI / AI consumers.
enum OutputFormat {
  text,
  json,
  summary,
  flameTree,
  flameTreeJson,
}

/// Report sections that can be included or excluded.
enum ReportSection {
  meta,
  frames,
  rebuild,
  timeline,
  drilldown,
  precision,
  compare,
}

const defaultReportSections = {
  ReportSection.meta,
  ReportSection.frames,
  ReportSection.rebuild,
  ReportSection.timeline,
  ReportSection.drilldown,
  ReportSection.precision,
};

/// Lighter analysis for [--format summary]: frames + precision only.
const summaryReportSections = {
  ReportSection.frames,
  ReportSection.precision,
};

/// How to pick a frame for drill-down analysis.
enum FrameTarget {
  none,
  byId,
  auto,
}

/// Options controlling analysis depth, filters, and output.
class AnalyzeOptions {
  const AnalyzeOptions({
    this.frameTarget = FrameTarget.none,
    this.frameId,
    this.topN = 25,
    this.budgetMsOverride,
    this.format = OutputFormat.text,
    this.sections = defaultReportSections,
    this.nameFilter,
    this.categories = const {},
    this.jankyOnly = false,
    this.worstFrames = 0,
    this.excludeEmbedder = false,
    this.comparePath,
    this.treeDepth = 16,
    this.minSelfMs = 0.3,
    this.treePhases = const {},
    this.treeTopPerLevel = 0,
    this.treeTopMetric = SliceTreeRankMetric.self,
    this.precisionFrameCount = 5,
  });

  /// Defaults tuned for one-screen triage (hot paths, no Embedder noise).
  factory AnalyzeOptions.forSummary() => const AnalyzeOptions(
        format: OutputFormat.summary,
        frameTarget: FrameTarget.auto,
        excludeEmbedder: true,
        sections: summaryReportSections,
      );

  final FrameTarget frameTarget;
  final int? frameId;
  final int topN;
  final double? budgetMsOverride;
  final OutputFormat format;
  final Set<ReportSection> sections;
  final String? nameFilter;
  final Set<String> categories;
  final bool jankyOnly;
  final int worstFrames;
  final bool excludeEmbedder;
  final String? comparePath;
  final int treeDepth;
  final double minSelfMs;
  final Set<String> treePhases;
  final int treeTopPerLevel;
  final SliceTreeRankMetric treeTopMetric;
  final int precisionFrameCount;

  bool get needsFlameTree =>
      format == OutputFormat.flameTree || format == OutputFormat.flameTreeJson;

  bool includes(ReportSection section) =>
      sections.contains(section) || sections.isEmpty;

  bool get needsTimeline =>
      includes(ReportSection.timeline) ||
      includes(ReportSection.precision) ||
      needsDrilldown ||
      needsFlameTree ||
      worstFrames > 0;

  bool get needsDrilldown =>
      frameTarget != FrameTarget.none || worstFrames > 0;

  TraceFilters get traceFilters => TraceFilters(
        namePattern: nameFilter,
        categories: categories,
        excludeEmbedder: excludeEmbedder,
      );
}
