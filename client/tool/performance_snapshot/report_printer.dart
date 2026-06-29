// ignore_for_file: avoid_print

import 'models.dart';
import 'options.dart';
import 'trace_decoder.dart';

void printPerformanceReport(
  PerformanceAnalysisResult result, {
  required AnalyzeOptions options,
}) {
  final sections = options.sections;

  if (sections.contains(ReportSection.meta) || sections.isEmpty) {
    _printHeader(result);
  }

  if (result.frameSummary == null) {
    if (sections.contains(ReportSection.frames) || sections.isEmpty) {
      print('\nNo flutterFrames in snapshot.');
    }
  } else if (sections.contains(ReportSection.frames) || sections.isEmpty) {
    _printFrameSummary(result.frameSummary!, options.jankyOnly);
  }

  if (sections.contains(ReportSection.rebuild) || sections.isEmpty) {
    _printRebuildSummary(result.rebuildSummary, options.topN);
  }

  if (sections.contains(ReportSection.timeline) || sections.isEmpty) {
    if (result.timeline == null) {
      if (sections.contains(ReportSection.timeline)) {
        print('\nNo traceBinary — timeline analysis skipped.');
      }
    } else {
      _printTimeline(result.timeline!, options.topN);
    }
  }

  if (sections.contains(ReportSection.compare) || sections.isEmpty) {
    if (result.comparison != null) {
      _printComparison(result.comparison!);
    }
  }

  if (sections.contains(ReportSection.drilldown) || sections.isEmpty) {
    _printDrilldownSection(result);
  }

  if (sections.contains(ReportSection.precision) || sections.isEmpty) {
    _printPrecisionSection(result.precision);
  }
}

void _printDrilldownSection(PerformanceAnalysisResult result) {
  if (result.missingFrameId != null) {
    print('\nFrame #${result.missingFrameId} not in flutterFrames list.');
  }
  if (result.worstFrameDrilldowns.isNotEmpty) {
    print('\n=== Worst Frame Drill-downs (${result.worstFrameDrilldowns.length}) ===');
    for (final drilldown in result.worstFrameDrilldowns) {
      _printFrameDrilldown(drilldown, compact: result.worstFrameDrilldowns.length > 1);
    }
  } else if (result.frameDrilldown != null) {
    _printFrameDrilldown(result.frameDrilldown!);
  } else if (result.slowestFrameTip != null) {
    print(
      '\nTip: pass --frame auto or --frame ${result.slowestFrameTip} '
      'to drill into the slowest frame.',
    );
  }
}

void _printHeader(PerformanceAnalysisResult result) {
  final snapshot = result.snapshot;
  final app = snapshot.connectedApp;

  print('=== DevTools Performance Snapshot ===');
  print('DevTools: ${snapshot.devToolsVersion}');
  print('Snapshot: ${snapshot.isDevToolsSnapshot ? 'yes' : 'no'}');
  print('Screen: ${snapshot.activeScreenId}');
  if (app != null) {
    print(
      'App: Flutter ${app.flutterVersion} on ${app.operatingSystem} '
      '(profile=${app.isProfileBuild}, dartVM=${app.isRunningOnDartVM})',
    );
  }
  print(
    'Refresh rate: ${snapshot.displayRefreshRateHz.toStringAsFixed(0)} Hz '
    '(jank budget ${result.budgetMs.toStringAsFixed(2)} ms)',
  );
  if (snapshot.selectedTab != null) {
    print(
      'Exported tab index: ${snapshot.selectedTab} (${result.exportedTabLabel})',
    );
  }
  if (result.traceBinaryKiB != null) {
    print('Trace binary: ${result.traceBinaryKiB!.toStringAsFixed(1)} KiB');
  }
  print('Rebuild stats: ${_rebuildStatusLabel(result.rebuildStatus)}');
  if (result.appliedFilters.isNotEmpty) {
    print('Active filters: ${result.appliedFilters}');
  }
}

String _rebuildStatusLabel(RebuildDataStatus status) => switch (status) {
      RebuildDataStatus.notCaptured => 'not captured',
      RebuildDataStatus.empty => 'empty',
      RebuildDataStatus.present => 'present',
    };

void _printFrameSummary(FrameSummary summary, bool jankyOnly) {
  print('\n=== Flutter Frames (${summary.totalCount} recorded) ===');
  if (!jankyOnly) {
    for (final stat in summary.stats) {
      print(_formatTimingStats(stat));
    }
  }
  print(
    '\nJanky frames (>${summary.budgetMs.toStringAsFixed(2)} ms): '
    '${summary.jankyCount}/${summary.totalCount}',
  );
  if (summary.jankyFrames.isEmpty) {
    print('  (none)');
    return;
  }

  print('  ${'Frame'.padRight(8)} ${'Total'.padLeft(8)} '
      '${'Build'.padLeft(8)} ${'Raster'.padLeft(8)} ${'Vsync'.padLeft(8)}  Bottleneck');
  for (final janky in summary.jankyFrames) {
    final f = janky.frame;
    print(
      '  #${f.number.toString().padRight(6)} '
      '${f.elapsedMs.toStringAsFixed(2).padLeft(8)} '
      '${f.buildMs.toStringAsFixed(2).padLeft(8)} '
      '${f.rasterMs.toStringAsFixed(2).padLeft(8)} '
      '${f.vsyncMs.toStringAsFixed(2).padLeft(8)}  ${janky.bottleneck}',
    );
  }
}

String _formatTimingStats(TimingStats stat) {
  if (stat.label.isEmpty) return '${stat.label}: (empty)';
  return '${stat.label}: min=${stat.minMs.toStringAsFixed(2)} '
      'p50=${stat.p50Ms.toStringAsFixed(2)} '
      'p95=${stat.p95Ms.toStringAsFixed(2)} '
      'max=${stat.maxMs.toStringAsFixed(2)} '
      'avg=${stat.avgMs.toStringAsFixed(2)} ms';
}

void _printRebuildSummary(RebuildSummary summary, int topN) {
  print('\n=== Widget Rebuild Stats ===');
  if (summary.status != RebuildDataStatus.present) {
    print('No rebuildCountModel data in snapshot.');
    print('Enable rebuild tracking in DevTools (Rebuild Stats tab) before export.');
    return;
  }

  print('Frames with rebuild data: ${summary.frameCount}');
  print('Known widget locations: ${summary.locationCount}');
  if (summary.topWidgets.isEmpty) {
    print('(no rebuild events recorded)');
    return;
  }

  print('\nTop $topN widgets by total rebuild count:');
  print('  ${'Rebuilds'.padLeft(8)}  Widget');
  for (final item in summary.topWidgets) {
    print('  ${item.buildCount.toString().padLeft(8)}  ${item.label}');
  }
}

void _printTimeline(TimelineAnalysis timeline, int topN) {
  final overview = timeline.overview;
  print('\n=== Perfetto Timeline ===');
  print('Completed slices: ${overview.sliceCount}');
  print('Instant events: ${overview.instantCount}');
  print('CPU samples: ${overview.cpuSampleCount}');
  print('Tracks: ${overview.trackCount}');
  print('UI frame markers: ${overview.uiFrameMarkerCount}');
  print('Raster frame markers: ${overview.rasterFrameMarkerCount}');
  if (overview.uiTrackName != null) {
    print('UI track: ${overview.uiTrackName}');
  }
  if (overview.rasterTrackName != null) {
    print('Raster track: ${overview.rasterTrackName}');
  }

  if (timeline.topSlices.isNotEmpty) {
    print('\n=== Top $topN Timeline Slices ===');
    print('  ${'Duration'.padLeft(10)}  ${'Track'.padRight(28)}  Event');
    for (final s in timeline.topSlices) {
      print(
        '  ${s.durationMs.toStringAsFixed(2).padLeft(8)} ms  '
        '${shortLabel(s.trackLabel, 28).padRight(28)}  ${s.name}',
      );
    }
  }

  if (timeline.aggregatedSlices.isNotEmpty) {
    print('\n=== Top slices aggregated by event name ===');
    print('  ${'Total'.padLeft(10)} ${'Max'.padLeft(10)} ${'Count'.padLeft(7)}  Event');
    for (final e in timeline.aggregatedSlices) {
      print(
        '  ${e.totalMs.toStringAsFixed(2).padLeft(8)} ms '
        '${e.maxMs.toStringAsFixed(2).padLeft(8)} ms '
        '${e.count.toString().padLeft(7)}  ${e.name}',
      );
    }
  }

  final instant = timeline.instantSummary;
  if (instant != null) {
    print('\n=== Instant Events (${instant.totalCount} total) ===');
    print('  ${'Count'.padLeft(8)}  Event');
    for (final entry in instant.topEvents) {
      print('  ${entry.value.toString().padLeft(8)}  ${entry.key}');
    }
  }

  final shader = timeline.shaderSummary;
  if (shader != null) {
    print('\n=== Shader Compilation ===');
    print('Shader slices: ${shader.sliceCount}');
    print('Shader instants: ${shader.instantCount}');
    if (shader.longestSliceMs != null) {
      print(
        'Longest shader slice: '
        '${shader.longestSliceMs!.toStringAsFixed(2)} ms '
        '(${shader.longestSliceName})',
      );
    }
  }

  final cpu = timeline.cpuSummary;
  if (cpu != null) {
    print('\n=== CPU Samples (${cpu.sampleCount} total) ===');
    print('  ${'Hits'.padLeft(8)}  Symbol (top of stack window)');
    for (final entry in cpu.topSymbols.entries) {
      print('  ${entry.value.toString().padLeft(8)}  ${entry.key}');
    }
  }
}

void _printComparison(SnapshotComparison comparison) {
  print('\n=== Snapshot Comparison ===');
  print('Baseline:  ${comparison.baselineLabel}');
  print('Candidate: ${comparison.candidateLabel}');
  print(
    'Janky frames: ${comparison.jankyCountBaseline} → '
    '${comparison.jankyCountCandidate} '
    '(Δ ${comparison.jankyCountCandidate - comparison.jankyCountBaseline})',
  );
  print(
    'Worst frame: ${comparison.worstFrameMsBaseline.toStringAsFixed(2)} → '
    '${comparison.worstFrameMsCandidate.toStringAsFixed(2)} ms '
    '(Δ ${(comparison.worstFrameMsCandidate - comparison.worstFrameMsBaseline).toStringAsFixed(2)} ms)',
  );
  print(
    'Avg frame: ${comparison.avgFrameMsBaseline.toStringAsFixed(2)} → '
    '${comparison.avgFrameMsCandidate.toStringAsFixed(2)} ms',
  );
  if (comparison.topSliceRegressions.isEmpty) {
    print('No slice regressions > 0.5 ms detected.');
    return;
  }
  print('\nTop slice regressions (max duration increased):');
  for (final r in comparison.topSliceRegressions) {
    print(
      '  +${r.deltaMs.toStringAsFixed(2)} ms  ${r.name} '
      '(${r.maxMsBaseline.toStringAsFixed(2)} → ${r.maxMsCandidate.toStringAsFixed(2)} ms)',
    );
  }
}

void _printFrameDrilldown(FrameDrilldown drilldown, {bool compact = false}) {
  final frame = drilldown.frame;
  print('\n=== Frame #${frame.number} Drill-down ===');
  print(
    'Frame timing: ${frame.elapsedMs.toStringAsFixed(2)} ms '
    '(build ${frame.buildMs.toStringAsFixed(2)}, '
    'raster ${frame.rasterMs.toStringAsFixed(2)}, '
    'vsync ${frame.vsyncMs.toStringAsFixed(2)}) → ${drilldown.bottleneck}',
  );

  if (compact) {
    if (drilldown.dartHotspots.isNotEmpty) {
      print('Top hotspot: ${drilldown.dartHotspots.first.name} '
          '(${drilldown.dartHotspots.first.durationMs.toStringAsFixed(2)} ms)');
    }
    return;
  }

  if (drilldown.timelineWindowMs != null) {
    print(
      'Timeline window: ${drilldown.timelineWindowMs!.toStringAsFixed(2)} ms '
      '(from ${drilldown.timelineWindowSource} markers)',
    );
  }

  print('\nWidget rebuilds in this frame:');
  if (drilldown.rebuilds.isEmpty) {
    print('  (none recorded)');
  } else {
    for (final item in drilldown.rebuilds) {
      print('  ${item.buildCount.toString().padLeft(5)}x  ${item.label}');
    }
  }

  if (drilldown.overlappingSlices.isEmpty) {
    print('\nNo timeline slices overlap this frame window.');
    return;
  }

  print('\nSlices overlapping frame window (${drilldown.overlappingSlices.length} shown):');
  print('  ${'Duration'.padLeft(10)}  ${'Track'.padRight(28)}  Event');
  for (final s in drilldown.overlappingSlices) {
    print(
      '  ${s.durationMs.toStringAsFixed(2).padLeft(8)} ms  '
      '${shortLabel(s.trackLabel, 28).padRight(28)}  ${s.name}',
    );
  }

  if (drilldown.dartHotspots.isNotEmpty) {
    print('\nDart build/layout hotspots in this frame:');
    for (final s in drilldown.dartHotspots) {
      print('  ${s.durationMs.toStringAsFixed(2).padLeft(8)} ms  ${s.name}');
    }
  }

  if (drilldown.overBudgetMs != null) {
    print('Over budget by ${drilldown.overBudgetMs!.toStringAsFixed(2)} ms.');
  }
}

void _printPrecisionSection(PrecisionAnalysis? precision) {
  if (precision == null) {
    print('\n=== Precision Analysis ===');
    print('No janky frames or traceBinary — precision analysis skipped.');
    return;
  }

  print('\n=== Precision Analysis (${precision.frameCountAnalyzed} janky frames) ===');
  final note = precision.rebuildNote;
  print(
    'Rebuild data: ${note.status} (precision impact: ${note.precisionImpact})',
  );
  print('  ${note.message}');

  print('\nFrame guides (which track to inspect):');
  for (final g in precision.frameGuides) {
    print(
      '  #${g.frameNumber} ${g.elapsedMs.toStringAsFixed(1)} ms '
      '→ ${g.bottleneck} → inspect ${g.primaryAnalysisTrack} track',
    );
  }

  if (precision.uiHotPaths.isNotEmpty) {
    print('\nAggregated UI hot paths:');
    for (final h in precision.uiHotPaths.take(10)) {
      print(
        '  ${h.totalSelfMs.toStringAsFixed(1)} ms self '
        '(${h.occurrenceCount}/${precision.frameCountAnalyzed} frames)  ${h.path}',
      );
    }
  }

  if (precision.rasterHotPaths.isNotEmpty) {
    print('\nAggregated raster hot paths:');
    for (final h in precision.rasterHotPaths.take(10)) {
      print(
        '  ${h.totalSelfMs.toStringAsFixed(1)} ms self '
        '(${h.occurrenceCount}/${precision.frameCountAnalyzed} frames)  ${h.path}',
      );
    }
  }

  if (precision.dartMethodHotspots.isNotEmpty) {
    print('\nAggregated Dart method hotspots:');
    for (final h in precision.dartMethodHotspots.take(10)) {
      print(
        '  ${h.totalMs.toStringAsFixed(1)} ms '
        '(${h.occurrenceCount}/${precision.frameCountAnalyzed} frames, '
        'max ${h.maxMsInSingleFrame.toStringAsFixed(1)} ms)  ${h.name}',
      );
    }
  }

  if (precision.dartHotPaths.isNotEmpty) {
    print('\nAggregated Dart hot paths (self time):');
    for (final h in precision.dartHotPaths.take(10)) {
      print(
        '  ${h.totalSelfMs.toStringAsFixed(1)} ms self '
        '(${h.occurrenceCount}/${precision.frameCountAnalyzed} frames)  ${h.path}',
      );
    }
  }

  if (precision.rebuildCorrelations.isNotEmpty) {
    print('\nRebuild ↔ slice correlations:');
    for (final c in precision.rebuildCorrelations.take(10)) {
      final loc = c.file != null && c.line != null
          ? ' @ ${c.file}:${c.line}'
          : '';
      final slice = c.matchedSlices.isEmpty
          ? ''
          : ' → ${c.matchedSlices.first.name} '
              '(${c.matchedSlices.first.selfMs.toStringAsFixed(1)} ms self, '
              '${c.matchedSlices.first.phase ?? '?'})';
      print(
        '  #${c.frameNumber} ${c.widgetName}$loc '
        '${c.rebuildCount}x rebuilds [${c.matchQuality}]$slice',
      );
    }
  }

  if (precision.unmatchedHighSelfSlices.isNotEmpty) {
    print('\nHigh self-time slices without rebuild match:');
    for (final u in precision.unmatchedHighSelfSlices.take(8)) {
      print(
        '  #${u.frameNumber} ${u.selfMs.toStringAsFixed(1)} ms '
        '[${u.track}] ${u.path}',
      );
    }
  }

  if (precision.unmatchedHighRebuilds.isNotEmpty) {
    print('\nFrequent rebuilds without timeline slice match:');
    for (final u in precision.unmatchedHighRebuilds.take(8)) {
      final loc =
          u.file != null && u.line != null ? ' @ ${u.file}:${u.line}' : '';
      print(
        '  #${u.frameNumber} ${u.widgetName}$loc ${u.rebuildCount}x rebuilds',
      );
    }
  }
}
