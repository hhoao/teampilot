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
    _printAppliedFilters(result);
    return;
  }

  final worst = frames.jankyFrames.isEmpty ? null : frames.jankyFrames.first;
  print(
    'Frames: ${frames.jankyCount}/${frames.totalCount} janky'
    '${worst == null ? '' : ' | worst #${worst.frame.number} ${worst.frame.elapsedMs.toStringAsFixed(1)} ms (${worst.bottleneck})'}',
  );

  if (frames.jankyCount == 0) {
    print('No janky frames over ${frames.budgetMs.toStringAsFixed(2)} ms budget.');
    _printAppliedFilters(result);
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
  if (precision?.traceCoverage != null) {
    print('\nTrace coverage:');
    for (final line in precision!.traceCoverage!.message.split('\n')) {
      print('  $line');
    }
  }

  if (precision != null) {
    _printPrecisionHighlights(precision, budgetMs: result.budgetMs);
  } else if (result.timeline == null) {
    print('\nHot paths: unavailable (no traceBinary in export).');
  } else {
    print('\nHot paths: unavailable (no janky frames in snapshot).');
  }

  _printAppliedFilters(result);
}

void _printPrecisionHighlights(
  PrecisionAnalysis precision, {
  required double budgetMs,
}) {
  final coverage = precision.traceCoverage;
  final tracedFramesLabel = coverage != null &&
          coverage.precisionFrameNumbers.isNotEmpty
      ? formatFrameList(coverage.precisionFrameNumbers)
      : null;
  final excludesWorst = coverage?.precisionExcludesWorstJanky ?? false;

  if (excludesWorst && coverage?.untracedWorstJanky != null) {
    final untraced = coverage!.untracedWorstJanky!;
    print('\nWorst janky frame (no timeline in export):');
    print(
      '  #${untraced.frameNumber} ${untraced.elapsedMs.toStringAsFixed(1)} ms '
      '(build ${untraced.buildMs.toStringAsFixed(1)}, '
      'raster ${untraced.rasterMs.toStringAsFixed(1)}, '
      'vsync ${untraced.vsyncMs.toStringAsFixed(1)}) '
      '→ ${untraced.bottleneck} '
      '(+${untraced.overBudgetMs.toStringAsFixed(1)} ms over '
      '${budgetMs.toStringAsFixed(2)} ms budget)',
    );
  }

  final note = precision.rebuildNote;
  if (note.precisionImpact != 'low') {
    print('\nRebuild data: ${note.status} (${note.precisionImpact} impact)');
    print('  ${note.message}');
  }

  if (precision.uiHotPaths.isNotEmpty) {
    final header = excludesWorst && tracedFramesLabel != null
        ? '\nUI hot paths (self time; frames $tracedFramesLabel; '
            'excludes #${coverage!.untracedWorstJanky!.frameNumber}):'
        : '\nUI hot paths (self time, ${precision.frameCountAnalyzed} janky frames):';
    print(header);
    for (final h in precision.uiHotPaths.take(5)) {
      print(
        '  ${h.totalSelfMs.toStringAsFixed(1)} ms '
        '(${h.occurrenceCount}/${precision.frameCountAnalyzed} frames, '
        '${formatFrameList(h.frameNumbers)})',
      );
      print('    ${shortenHotPath(h.path)}');
    }
  }

  if (precision.dartMethodHotspots.isNotEmpty) {
    final header = excludesWorst && tracedFramesLabel != null
        ? '\nDart method hotspots (frames $tracedFramesLabel; '
            'excludes #${coverage!.untracedWorstJanky!.frameNumber}):'
        : '\nDart method hotspots (layout/paint on Dart track, '
            '${precision.frameCountAnalyzed} janky frames):';
    print(header);
    for (final h in precision.dartMethodHotspots.take(5)) {
      print(
        '  ${h.totalMs.toStringAsFixed(1)} ms '
        '(${h.occurrenceCount}/${precision.frameCountAnalyzed} frames, '
        'max ${h.maxMsInSingleFrame.toStringAsFixed(1)} ms, '
        '${formatFrameList(h.frameNumbers)})',
      );
      print('    ${h.name}');
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
    final header = excludesWorst && tracedFramesLabel != null
        ? '\nRebuild ↔ timeline slice (frames $tracedFramesLabel):'
        : '\nRebuild ↔ timeline slice:';
    print(header);
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

  print('\nPer-frame breakdown:');
  for (final g in precision.frameGuides.take(4)) {
    final track = g.primaryAnalysisTrack == 'flutterFrames-only'
        ? 'flutterFrames only'
        : g.primaryAnalysisTrack;
    print(
      '  #${g.frameNumber} ${g.elapsedMs.toStringAsFixed(0)} ms '
      '→ ${g.bottleneck} → $track',
    );
  }
}

void _printAppliedFilters(PerformanceAnalysisResult result) {
  if (result.appliedFilters['excludeEmbedder'] == true) {
    print('\nApplied filters: Embedder slices excluded');
  }
}
