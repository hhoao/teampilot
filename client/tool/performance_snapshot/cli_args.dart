import 'options.dart';
import 'slice_tree.dart';

/// Parses CLI arguments into [AnalyzeOptions].
AnalyzeOptions parseAnalyzeOptions(List<String> args) {
  final frameRaw = _readOption(args, '--frame');

  final formatRaw = (_readOption(args, '--format') ?? 'text').toLowerCase();
  final format = switch (formatRaw) {
    'json' => OutputFormat.json,
    'summary' => OutputFormat.summary,
    'flame-tree' || 'flametree' => OutputFormat.flameTree,
    'flame-tree-json' || 'flametreejson' => OutputFormat.flameTreeJson,
    _ => OutputFormat.text,
  };

  FrameTarget frameTarget = FrameTarget.none;
  int? frameId;
  if (frameRaw != null) {
    if (frameRaw.toLowerCase() == 'auto') {
      frameTarget = FrameTarget.auto;
    } else {
      frameId = int.tryParse(frameRaw);
      if (frameId != null) frameTarget = FrameTarget.byId;
    }
  } else if (format == OutputFormat.flameTree ||
      format == OutputFormat.flameTreeJson ||
      format == OutputFormat.summary) {
    frameTarget = FrameTarget.auto;
  }

  final sectionsRaw = _readOption(args, '--sections');
  final sections = sectionsRaw == null
      ? (format == OutputFormat.summary
          ? summaryReportSections
          : defaultReportSections)
      : _parseSections(sectionsRaw);

  final categoriesRaw = _readOption(args, '--category');
  final categories = categoriesRaw == null
      ? <String>{}
      : categoriesRaw
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toSet();

  final treePhasesRaw = _readOption(args, '--tree-phase');
  final treePhases = treePhasesRaw == null
      ? <String>{}
      : treePhasesRaw
          .split(',')
          .map((s) => s.trim().toLowerCase())
          .where((s) => s.isNotEmpty)
          .toSet();

  final treeFull = args.contains('--tree-full');
  final treeTopRaw = _readOption(args, '--tree-top');
  int treeTopPerLevel;
  if (treeFull) {
    treeTopPerLevel = 0;
  } else if (treeTopRaw != null) {
    treeTopPerLevel = int.tryParse(treeTopRaw) ?? 0;
  } else if (format == OutputFormat.flameTree ||
      format == OutputFormat.flameTreeJson) {
    treeTopPerLevel = 2;
  } else {
    treeTopPerLevel = 0;
  }

  final metricRaw =
      (_readOption(args, '--tree-top-metric') ?? 'self').toLowerCase();
  final treeTopMetric = metricRaw == 'total'
      ? SliceTreeRankMetric.total
      : SliceTreeRankMetric.self;

  final excludeEmbedder =
      args.contains('--no-embedder') ||
      (format == OutputFormat.summary && !args.contains('--embedder'));

  return AnalyzeOptions(
    frameTarget: frameTarget,
    frameId: frameId,
    topN: int.tryParse(_readOption(args, '--top') ?? '25') ?? 25,
    budgetMsOverride: _readBudgetOverride(args),
    format: format,
    sections: sections,
    nameFilter: _readOption(args, '--filter'),
    categories: categories,
    jankyOnly: args.contains('--janky-only'),
    worstFrames: int.tryParse(_readOption(args, '--worst-frames') ?? '0') ?? 0,
    excludeEmbedder: excludeEmbedder,
    comparePath: _readOption(args, '--compare'),
    treeDepth: int.tryParse(_readOption(args, '--tree-depth') ?? '16') ?? 16,
    minSelfMs: double.tryParse(_readOption(args, '--min-self-ms') ?? '0.3') ?? 0.3,
    treePhases: treePhases,
    treeTopPerLevel: treeTopPerLevel,
    treeTopMetric: treeTopMetric,
    precisionFrameCount:
        int.tryParse(_readOption(args, '--precision-frames') ?? '5') ?? 5,
  );
}

Set<ReportSection> _parseSections(String raw) {
  final names = raw.split(',').map((s) => s.trim().toLowerCase());
  final out = <ReportSection>{};
  for (final name in names) {
    final section = switch (name) {
      'meta' => ReportSection.meta,
      'frames' => ReportSection.frames,
      'rebuild' => ReportSection.rebuild,
      'timeline' => ReportSection.timeline,
      'drilldown' => ReportSection.drilldown,
      'precision' => ReportSection.precision,
      'compare' => ReportSection.compare,
      'all' => null,
      _ => null,
    };
    if (section == null && name == 'all') {
      return defaultReportSections;
    }
    if (section != null) out.add(section);
  }
  return out.isEmpty ? defaultReportSections : out;
}

String? _readOption(List<String> args, String name) {
  final i = args.indexOf(name);
  if (i < 0 || i + 1 >= args.length) return null;
  return args[i + 1];
}

double? _readBudgetOverride(List<String> args) {
  final raw = _readOption(args, '--budget');
  if (raw == null) return null;
  return double.tryParse(raw);
}

String analyzeUsageText() => '''
Analyze Flutter DevTools performance snapshot JSON.

Usage:
  dart run tool/analyze_performance_json.dart <snapshot.json> [options]

Options:
  --format <text|json|summary|flame-tree|flame-tree-json>
                                 Output format (default: text; summary = triage + hot paths)
  --sections <list>              Comma-separated: meta,frames,rebuild,timeline,drilldown,precision,compare,all
  --frame <id|auto>              Drill into frame (auto = slowest janky; default for summary/flame-tree)
  --top <n>                      Top N items in ranked lists (default: 25)
  --budget <ms>                  Jank threshold override (default: 1000 / displayRefreshRate)
  --filter <pattern>             Substring filter on slice/event names (case-insensitive)
  --category <Dart,Embedder>     Filter timeline by category
  --janky-only                   Frame section: only list janky frames (skip stats)
  --worst-frames <n>             Brief drill-down for top N janky frames
  --precision-frames <n>         Janky frames for hot-path / correlation (default: 5)
  --no-embedder                  Exclude Embedder track slices (default for --format summary)
  --embedder                     Include Embedder slices when using --format summary
  --compare <baseline.json>      Compare candidate snapshot against a baseline export
  --tree-depth <n>               Max nesting depth for flame-tree (default: 16)
  --min-self-ms <ms>             Hide self-time hotspots below this (default: 0.3)
  --tree-phase <build,layout>    Only show subtrees under these phase roots
  --tree-top <n>                 Keep top N children per level (default: 2 for flame-tree)
  --tree-top-metric <self|total> Rank siblings by self or total ms (default: self)
  --tree-full                    Disable per-level top-N pruning (show full tree)
  -h, --help                     Show this help

Flame tree example:
  dart run tool/analyze_performance_json.dart snapshot.json \\
    --format flame-tree --frame 1515 --no-embedder
''';
