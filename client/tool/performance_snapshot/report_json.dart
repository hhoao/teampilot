import 'dart:convert';

import 'models.dart';
import 'options.dart';

/// Serializes [PerformanceAnalysisResult] for AI / programmatic consumers.
String encodePerformanceReportJson(PerformanceAnalysisResult result) {
  return const JsonEncoder.withIndent('  ').convert(result.toJsonMap());
}

extension PerformanceAnalysisResultJson on PerformanceAnalysisResult {
  Map<String, Object?> toJsonMap() => {
        'budgetMs': budgetMs,
        'exportedTabLabel': exportedTabLabel,
        'traceBinaryKiB': traceBinaryKiB,
        'rebuildStatus': rebuildStatus.name,
        'appliedFilters': appliedFilters,
        if (appliedFilters.isNotEmpty) 'filtersNote': 'filters applied to timeline slices',
        'meta': _metaJson(),
        if (frameSummary != null) 'frames': _framesJson(frameSummary!),
        'rebuild': _rebuildJson(rebuildSummary),
        if (timeline != null) 'timeline': _timelineJson(timeline!),
        if (frameDrilldown != null) 'frameDrilldown': _drilldownJson(frameDrilldown!),
        if (worstFrameDrilldowns.isNotEmpty)
          'worstFrameDrilldowns': [
            for (final d in worstFrameDrilldowns) _drilldownJson(d),
          ],
        if (comparison != null) 'comparison': _comparisonJson(comparison!),
        if (missingFrameId != null) 'missingFrameId': missingFrameId,
        if (slowestFrameTip != null) 'slowestFrameTip': slowestFrameTip,
      };

  Map<String, Object?> _metaJson() {
    final s = snapshot;
    final app = s.connectedApp;
    return {
      'devToolsVersion': s.devToolsVersion,
      'isDevToolsSnapshot': s.isDevToolsSnapshot,
      'activeScreenId': s.activeScreenId,
      'displayRefreshRateHz': s.displayRefreshRateHz,
      'selectedFrameId': s.selectedFrameId,
      'selectedTab': s.selectedTab,
      if (app != null)
        'app': {
          'flutterVersion': app.flutterVersion,
          'operatingSystem': app.operatingSystem,
          'isProfileBuild': app.isProfileBuild,
          'isRunningOnDartVM': app.isRunningOnDartVM,
        },
    };
  }

  Map<String, Object?> _framesJson(FrameSummary summary) => {
        'totalCount': summary.totalCount,
        'jankyCount': summary.jankyCount,
        'budgetMs': summary.budgetMs,
        'stats': [
          for (final stat in summary.stats)
            {
              'label': stat.label,
              'minMs': stat.minMs,
              'p50Ms': stat.p50Ms,
              'p95Ms': stat.p95Ms,
              'maxMs': stat.maxMs,
              'avgMs': stat.avgMs,
            },
        ],
        'jankyFrames': [
          for (final j in summary.jankyFrames)
            {
              'number': j.frame.number,
              'elapsedMs': j.frame.elapsedMs,
              'buildMs': j.frame.buildMs,
              'rasterMs': j.frame.rasterMs,
              'vsyncMs': j.frame.vsyncMs,
              'bottleneck': j.bottleneck,
            },
        ],
      };

  Map<String, Object?> _rebuildJson(RebuildSummary summary) => {
        'status': summary.status.name,
        'frameCount': summary.frameCount,
        'locationCount': summary.locationCount,
        'topWidgets': [
          for (final w in summary.topWidgets)
            {
              'name': w.name,
              'file': w.file,
              'line': w.line,
              'column': w.column,
              'buildCount': w.buildCount,
              'label': w.label,
            },
        ],
      };

  Map<String, Object?> _timelineJson(TimelineAnalysis timeline) => {
        'overview': {
          'sliceCount': timeline.overview.sliceCount,
          'instantCount': timeline.overview.instantCount,
          'cpuSampleCount': timeline.overview.cpuSampleCount,
          'trackCount': timeline.overview.trackCount,
          'uiFrameMarkerCount': timeline.overview.uiFrameMarkerCount,
          'rasterFrameMarkerCount': timeline.overview.rasterFrameMarkerCount,
          'uiTrackName': timeline.overview.uiTrackName,
          'rasterTrackName': timeline.overview.rasterTrackName,
        },
        'topSlices': [
          for (final s in timeline.topSlices)
            {
              'durationMs': s.durationMs,
              'track': s.trackLabel,
              'name': s.name,
            },
        ],
        'aggregatedSlices': [
          for (final e in timeline.aggregatedSlices)
            {
              'name': e.name,
              'totalMs': e.totalMs,
              'maxMs': e.maxMs,
              'count': e.count,
            },
        ],
        if (timeline.instantSummary != null)
          'instantEvents': {
            'totalCount': timeline.instantSummary!.totalCount,
            'top': [
              for (final e in timeline.instantSummary!.topEvents)
                {'name': e.key, 'count': e.value},
            ],
          },
        if (timeline.shaderSummary != null)
          'shader': {
            'sliceCount': timeline.shaderSummary!.sliceCount,
            'instantCount': timeline.shaderSummary!.instantCount,
            'longestSliceMs': timeline.shaderSummary!.longestSliceMs,
            'longestSliceName': timeline.shaderSummary!.longestSliceName,
          },
        if (timeline.cpuSummary != null)
          'cpu': {
            'sampleCount': timeline.cpuSummary!.sampleCount,
            'topSymbols': timeline.cpuSummary!.topSymbols,
          },
      };

  Map<String, Object?> _drilldownJson(FrameDrilldown d) => {
        'frameNumber': d.frame.number,
        'elapsedMs': d.frame.elapsedMs,
        'buildMs': d.frame.buildMs,
        'rasterMs': d.frame.rasterMs,
        'vsyncMs': d.frame.vsyncMs,
        'bottleneck': d.bottleneck,
        'timelineWindowMs': d.timelineWindowMs,
        'timelineWindowSource': d.timelineWindowSource,
        'uiBeginMarkerMs': d.uiBeginMarkerMs,
        'rasterMarkerMs': d.rasterMarkerMs,
        'overBudgetMs': d.overBudgetMs,
        'dartUiSliceMs': d.dartUiSliceMs,
        'rasterSliceMs': d.rasterSliceMs,
        'rebuilds': [
          for (final r in d.rebuilds)
            {'label': r.label, 'buildCount': r.buildCount},
        ],
        'overlappingSlices': [
          for (final s in d.overlappingSlices)
            {
              'durationMs': s.durationMs,
              'track': s.trackLabel,
              'name': s.name,
            },
        ],
        'dartHotspots': [
          for (final s in d.dartHotspots)
            {'durationMs': s.durationMs, 'name': s.name},
        ],
        'frameCpuSymbols': d.frameCpuSymbols,
      };

  Map<String, Object?> _comparisonJson(SnapshotComparison c) => {
        'baseline': c.baselineLabel,
        'candidate': c.candidateLabel,
        'jankyCount': {
          'baseline': c.jankyCountBaseline,
          'candidate': c.jankyCountCandidate,
          'delta': c.jankyCountCandidate - c.jankyCountBaseline,
        },
        'worstFrameMs': {
          'baseline': c.worstFrameMsBaseline,
          'candidate': c.worstFrameMsCandidate,
          'delta': c.worstFrameMsCandidate - c.worstFrameMsBaseline,
        },
        'avgFrameMs': {
          'baseline': c.avgFrameMsBaseline,
          'candidate': c.avgFrameMsCandidate,
          'delta': c.avgFrameMsCandidate - c.avgFrameMsBaseline,
        },
        'topSliceRegressions': [
          for (final r in c.topSliceRegressions)
            {
              'name': r.name,
              'maxMsBaseline': r.maxMsBaseline,
              'maxMsCandidate': r.maxMsCandidate,
              'deltaMs': r.deltaMs,
            },
        ],
      };
}

/// Filters JSON map to requested sections.
Map<String, Object?> filterJsonBySections(
  Map<String, Object?> json,
  Set<ReportSection> sections,
) {
  if (sections.isEmpty) return json;
  final out = <String, Object?>{};
  void keep(String key, ReportSection section) {
    if (sections.contains(section) && json.containsKey(key)) {
      out[key] = json[key];
    }
  }

  keep('meta', ReportSection.meta);
  keep('frames', ReportSection.frames);
  keep('rebuild', ReportSection.rebuild);
  keep('timeline', ReportSection.timeline);
  keep('frameDrilldown', ReportSection.drilldown);
  keep('worstFrameDrilldowns', ReportSection.drilldown);
  keep('comparison', ReportSection.compare);

  for (final key in ['budgetMs', 'appliedFilters', 'rebuildStatus', 'traceBinaryKiB']) {
    if (json.containsKey(key)) out[key] = json[key];
  }
  return out;
}
