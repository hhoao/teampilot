// ignore_for_file: avoid_print

import 'models.dart';

import 'summary_format.dart';

/// One-screen triage for AI / humans: jank stats + precision hot paths.
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
    _printNextSteps(result, worstFrameNumber: null);
    return;
  }

  final worst = frames.jankyFrames.isEmpty ? null : frames.jankyFrames.first;
  print(
    'Frames: ${frames.jankyCount}/${frames.totalCount} janky'
    '${worst == null ? '' : ' | worst #${worst.frame.number} ${worst.frame.elapsedMs.toStringAsFixed(1)} ms (${worst.bottleneck})'}',
  );

  if (frames.jankyCount == 0) {
    print('No janky frames over ${frames.budgetMs.toStringAsFixed(2)} ms budget.');
    _printNextSteps(result, worstFrameNumber: null);
    return;
  }

  print('Top janky:');
  for (final j in frames.jankyFrames.take(3)) {
    final f = j.frame;
    print(
      '  #${f.number} ${f.elapsedMs.toStringAsFixed(1)} ms '
      '(build ${f.buildMs.toStringAsFixed(1)}, raster ${f.rasterMs.toStringAsFixed(1)}) '
      '→ ${j.bottleneck}',
    );
  }

  final precision = result.precision;
  if (precision != null) {
    _printPrecisionHighlights(precision);
  } else if (result.timeline == null) {
    print(
      '\nHot paths: unavailable (no traceBinary in export). '
      'Re-export from DevTools Performance with timeline data.',
    );
  } else {
    print('\nHot paths: unavailable (no janky frames in snapshot).');
  }

  _printNextSteps(result, worstFrameNumber: worst?.frame.number);
}

void _printPrecisionHighlights(PrecisionAnalysis precision) {
  final note = precision.rebuildNote;
  if (note.precisionImpact != 'low') {
    print('\nRebuild data: ${note.status} (${note.precisionImpact} impact)');
    print('  ${note.message}');
  }

  if (precision.uiHotPaths.isNotEmpty) {
    print(
      '\nUI hot paths (self time, ${precision.frameCountAnalyzed} janky frames):',
    );
    for (final h in precision.uiHotPaths.take(5)) {
      print(
        '  ${h.totalSelfMs.toStringAsFixed(1)} ms '
        '(${h.occurrenceCount}/${precision.frameCountAnalyzed} frames, '
        '${formatFrameList(h.frameNumbers)})',
      );
      print('    ${shortenHotPath(h.path)}');
    }
  }

  final rasterGuides = precision.frameGuides
      .where((g) => g.primaryAnalysisTrack == 'raster')
      .toList();
  if (precision.rasterHotPaths.isNotEmpty &&
      (rasterGuides.isNotEmpty ||
          precision.rasterHotPaths.first.totalSelfMs >= 5)) {
    print('\nRaster hot paths:');
    for (final h in precision.rasterHotPaths.take(3)) {
      print(
        '  ${h.totalSelfMs.toStringAsFixed(1)} ms '
        '(${formatFrameList(h.frameNumbers)})  ${shortenHotPath(h.path)}',
      );
    }
  }

  if (precision.rebuildCorrelations.isNotEmpty) {
    print('\nRebuild ↔ timeline slice:');
    for (final c in precision.rebuildCorrelations.take(5)) {
      final loc =
          c.file != null && c.line != null ? ' @ ${c.file}:${c.line}' : '';
      final slice = c.matchedSlices.isEmpty
          ? ''
          : ' → ${c.matchedSlices.first.name} '
              '${c.matchedSlices.first.selfMs.toStringAsFixed(1)} ms self'
              '${c.matchedSlices.first.phase != null ? ' (${c.matchedSlices.first.phase})' : ''}';
      print(
        '  #${c.frameNumber} ${c.widgetName}$loc '
        '${c.rebuildCount}x [${c.matchQuality}]$slice',
      );
    }
  }

  print('\nInspect track per frame:');
  for (final g in precision.frameGuides.take(3)) {
    print(
      '  #${g.frameNumber} ${g.elapsedMs.toStringAsFixed(0)} ms '
      '→ ${g.bottleneck} → ${g.primaryAnalysisTrack}',
    );
  }
}

void _printNextSteps(PerformanceAnalysisResult result, {int? worstFrameNumber}) {
  final frameArg = worstFrameNumber?.toString() ?? 'auto';
  print('\nNext steps:');
  print(
    '  dart run tool/analyze_performance_json.dart <snapshot> '
    '--format json --no-embedder --sections precision,frames',
  );
  print(
    '  dart run tool/analyze_performance_json.dart <snapshot> '
    '--format flame-tree-json --frame $frameArg --no-embedder',
  );
  if (result.appliedFilters['excludeEmbedder'] == true) {
    print('  (summary excludes Embedder slices by default)');
  }
}
