import 'trace_filters.dart';

/// Output format for CLI / AI consumers.
enum OutputFormat {
  text,
  json,
  summary,
}

/// Report sections that can be included or excluded.
enum ReportSection {
  meta,
  frames,
  rebuild,
  timeline,
  drilldown,
  compare,
}

const defaultReportSections = {
  ReportSection.meta,
  ReportSection.frames,
  ReportSection.rebuild,
  ReportSection.timeline,
  ReportSection.drilldown,
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
  });

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

  bool includes(ReportSection section) =>
      sections.contains(section) || sections.isEmpty;

  bool get needsTimeline =>
      includes(ReportSection.timeline) || needsDrilldown || worstFrames > 0;

  bool get needsDrilldown =>
      frameTarget != FrameTarget.none || worstFrames > 0;

  TraceFilters get traceFilters => TraceFilters(
        namePattern: nameFilter,
        categories: categories,
        excludeEmbedder: excludeEmbedder,
      );
}
