import 'options.dart';

/// Parses CLI arguments into [AnalyzeOptions].
AnalyzeOptions parseAnalyzeOptions(List<String> args) {
  final frameRaw = _readOption(args, '--frame');
  FrameTarget frameTarget = FrameTarget.none;
  int? frameId;
  if (frameRaw != null) {
    if (frameRaw.toLowerCase() == 'auto') {
      frameTarget = FrameTarget.auto;
    } else {
      frameId = int.tryParse(frameRaw);
      if (frameId != null) frameTarget = FrameTarget.byId;
    }
  }

  final formatRaw = (_readOption(args, '--format') ?? 'text').toLowerCase();
  final format = switch (formatRaw) {
    'json' => OutputFormat.json,
    'summary' => OutputFormat.summary,
    _ => OutputFormat.text,
  };

  final sectionsRaw = _readOption(args, '--sections');
  final sections = sectionsRaw == null
      ? defaultReportSections
      : _parseSections(sectionsRaw);

  final categoriesRaw = _readOption(args, '--category');
  final categories = categoriesRaw == null
      ? <String>{}
      : categoriesRaw.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toSet();

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
    excludeEmbedder: args.contains('--no-embedder'),
    comparePath: _readOption(args, '--compare'),
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
  --format <text|json|summary>   Output format (default: text)
  --sections <list>              Comma-separated: meta,frames,rebuild,timeline,drilldown,compare,all
  --frame <id|auto>              Drill into frame (auto = slowest janky frame)
  --top <n>                      Top N items in ranked lists (default: 25)
  --budget <ms>                  Jank threshold override (default: 1000 / displayRefreshRate)
  --filter <pattern>             Substring filter on slice/event names (case-insensitive)
  --category <Dart,Embedder>     Filter timeline by category
  --janky-only                   Frame section: only list janky frames (skip stats)
  --worst-frames <n>             Brief drill-down for top N janky frames
  --no-embedder                  Exclude Embedder track slices from timeline
  --compare <baseline.json>      Compare candidate snapshot against a baseline export
  -h, --help                     Show this help
''';
