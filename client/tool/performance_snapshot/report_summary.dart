// ignore_for_file: avoid_print

import 'models.dart';

/// One-screen executive summary for AI first-pass triage.
void printPerformanceSummary(PerformanceAnalysisResult result) {
  final s = result.snapshot;
  final app = s.connectedApp;
  print('PERFORMANCE SUMMARY');
  print(
    'App: Flutter ${app?.flutterVersion ?? '?'} on ${app?.operatingSystem ?? '?'} '
    '| ${s.displayRefreshRateHz.toStringAsFixed(0)} Hz '
    '| budget ${result.budgetMs.toStringAsFixed(2)} ms',
  );

  final frames = result.frameSummary;
  if (frames == null) {
    print('Frames: none');
    return;
  }

  print(
    'Frames: ${frames.jankyCount}/${frames.totalCount} janky '
    '(worst ${frames.jankyFrames.isEmpty ? '?' : frames.jankyFrames.first.frame.elapsedMs.toStringAsFixed(1)} ms)',
  );

  if (frames.jankyFrames.isNotEmpty) {
    print('Top janky:');
    for (final j in frames.jankyFrames.take(3)) {
      final f = j.frame;
      print(
        '  #${f.number} ${f.elapsedMs.toStringAsFixed(1)} ms '
        '(build ${f.buildMs.toStringAsFixed(1)}, raster ${f.rasterMs.toStringAsFixed(1)}) '
        '→ ${j.bottleneck}',
      );
    }
  }

  final timeline = result.timeline;
  if (timeline != null && timeline.topSlices.isNotEmpty) {
    print('Top timeline slices:');
    for (final slice in timeline.topSlices.take(5)) {
      print(
        '  ${slice.durationMs.toStringAsFixed(1)} ms ${slice.trackLabel}::${slice.name}',
      );
    }
  }

  final drill = result.frameDrilldown ?? result.worstFrameDrilldowns.firstOrNull;
  if (drill != null) {
    print(
      'Primary bottleneck frame #${drill.frame.number}: ${drill.bottleneck} '
      '(over budget ${drill.overBudgetMs?.toStringAsFixed(1) ?? '0'} ms)',
    );
    if (drill.dartHotspots.isNotEmpty) {
      print(
        'Hotspot: ${drill.dartHotspots.first.name} '
        '(${drill.dartHotspots.first.durationMs.toStringAsFixed(1)} ms)',
      );
    }
  } else if (result.slowestFrameTip != null) {
    print('Tip: re-run with --frame auto or --frame ${result.slowestFrameTip}');
  }

  if (result.comparison != null) {
    final c = result.comparison!;
    print(
      'Compare vs ${c.baselineLabel}: '
      'janky ${c.jankyCountBaseline}→${c.jankyCountCandidate}, '
      'worst ${c.worstFrameMsBaseline.toStringAsFixed(1)}→'
      '${c.worstFrameMsCandidate.toStringAsFixed(1)} ms',
    );
  }

  if (result.appliedFilters.isNotEmpty) {
    print('Filters: ${result.appliedFilters}');
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    if (!it.moveNext()) return null;
    return it.current;
  }
}
