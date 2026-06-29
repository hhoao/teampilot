// ignore_for_file: avoid_print

import 'dart:convert';

import 'flame_tree_builder.dart';
import 'slice_tree.dart';

void printFlameTreeReport(FlameTreeAnalysis analysis) {
  final frame = analysis.frame;
  print('=== Flame tree — frame #${frame.number} ===');
  print(
    'Frame: ${frame.elapsedMs.toStringAsFixed(2)} ms '
    '(build ${frame.buildMs.toStringAsFixed(1)}, '
    'raster ${frame.rasterMs.toStringAsFixed(1)}) '
    'budget ${analysis.budgetMs.toStringAsFixed(2)} ms',
  );
  if (analysis.timelineWindowMs != null) {
    print(
      'Timeline window: ${analysis.timelineWindowMs!.toStringAsFixed(2)} ms '
      '(${analysis.sliceCountInWindow} slices)',
    );
  }
  if (analysis.appliedFilters['treeTopPerLevel'] != null) {
    print(
      'Pruning: top ${analysis.appliedFilters['treeTopPerLevel']} children '
      'per level by ${analysis.appliedFilters['treeTopMetric']}',
    );
  }
  if (analysis.traceCoverageWarning != null) {
    print('');
    for (final line in analysis.traceCoverageWarning!.split('\n')) {
      print('WARNING: $line');
    }
  }
  print('');

  if (analysis.roots.isEmpty) {
    print('No nested UI or Dart slices in this frame window.');
    if (analysis.suggestedFrameNumber != null) {
      print(
        'Tip: re-run with --frame ${analysis.suggestedFrameNumber} '
        '(slowest janky frame that has timeline data).',
      );
    } else {
      print('Tip: ensure traceBinary is present and try without --filter.');
    }
    return;
  }

  print('Nested tree (total ms, self ms):');
  final forestOmitted = analysis.forestOmitted;
  if (forestOmitted != null && forestOmitted.count > 0) {
    print(
      '  … +${forestOmitted.count} root branches omitted '
      '(${forestOmitted.selfMs.toStringAsFixed(2)} ms self)',
    );
  }
  for (final root in analysis.roots) {
    _printNode(root, 0);
  }

  if (analysis.topSelfTime.isNotEmpty) {
    print('\nTop self time (leaf work not attributed to children):');
    for (final entry in analysis.topSelfTime.take(20)) {
      print(
        '  ${entry.selfMs.toStringAsFixed(2).padLeft(8)} ms  '
        '${entry.name}  (${entry.path})',
      );
    }
  }
}

void _printNode(SliceTreeNode node, int depth) {
  final indent = '  ' * depth;
  final self = node.selfMsDirect;
  final total = node.totalMs;
  final track = node.slice.track.contains('.ui') ? '' : ' [${node.slice.trackLabel}]';
  print(
    '$indent${node.slice.name}$track  '
    '${total.toStringAsFixed(2)} ms total, '
    '${self.toStringAsFixed(2)} ms self',
  );
  for (final child in node.children) {
    _printNode(child, depth + 1);
  }
  if (node.omittedSiblingCount > 0) {
    final indent = '  ' * (depth + 1);
    print(
      '$indent… +${node.omittedSiblingCount} siblings omitted '
      '(${node.omittedSiblingSelfMs.toStringAsFixed(2)} ms self)',
    );
  }
}

String encodeFlameTreeJson(FlameTreeAnalysis analysis) {
  final map = {
    'frame': {
      'number': analysis.frame.number,
      'elapsedMs': analysis.frame.elapsedMs,
      'buildMs': analysis.frame.buildMs,
      'rasterMs': analysis.frame.rasterMs,
      'vsyncMs': analysis.frame.vsyncMs,
    },
    'budgetMs': analysis.budgetMs,
    'timelineWindowMs': analysis.timelineWindowMs,
    'sliceCountInWindow': analysis.sliceCountInWindow,
    'appliedFilters': analysis.appliedFilters,
    if (analysis.traceCoverageWarning != null)
      'traceCoverageWarning': analysis.traceCoverageWarning,
    if (analysis.suggestedFrameNumber != null)
      'suggestedFrameNumber': analysis.suggestedFrameNumber,
    if (analysis.forestOmitted != null)
      'forestOmitted': {
        'count': analysis.forestOmitted!.count,
        'selfMs': analysis.forestOmitted!.selfMs,
      },
    'roots': [for (final r in analysis.roots) _nodeToJson(r)],
    'topSelfTime': [
      for (final e in analysis.topSelfTime)
        {
          'name': e.name,
          'track': e.track,
          'totalMs': e.totalMs,
          'selfMs': e.selfMs,
          'path': e.path,
        },
    ],
  };
  return const JsonEncoder.withIndent('  ').convert(map);
}

Map<String, Object?> _nodeToJson(SliceTreeNode node) => {
      'name': node.slice.name,
      'track': node.slice.trackLabel,
      'category': node.slice.category,
      'totalMs': node.totalMs,
      'selfMs': node.selfMsDirect,
      if (node.omittedSiblingCount > 0)
        'omittedSiblingCount': node.omittedSiblingCount,
      if (node.omittedSiblingCount > 0)
        'omittedSiblingSelfMs': node.omittedSiblingSelfMs,
      'children': [for (final c in node.children) _nodeToJson(c)],
    };
