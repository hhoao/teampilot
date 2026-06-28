// ignore_for_file: avoid_print
//
// Analyzes Flutter DevTools performance snapshot JSON exports.
//
// Usage (from `client/`):
//   dart run tool/analyze_performance_json.dart /path/to/snapshot.json
//   dart run tool/analyze_performance_json.dart /path/to/snapshot.json --format json
//   dart run tool/analyze_performance_json.dart /path/to/snapshot.json --frame auto --filter Panel

import 'dart:convert';
import 'dart:io';

import 'performance_snapshot/analyzer.dart';
import 'performance_snapshot/cli_args.dart';
import 'performance_snapshot/models.dart';
import 'performance_snapshot/options.dart';
import 'performance_snapshot/report_json.dart';
import 'performance_snapshot/report_printer.dart';
import 'performance_snapshot/report_summary.dart';
import 'performance_snapshot/snapshot_loader.dart';

void main(List<String> args) {
  if (args.isEmpty || args.contains('-h') || args.contains('--help')) {
    print(analyzeUsageText());
    exit(args.isEmpty ? 1 : 0);
  }

  final path = args.firstWhere((a) => !a.startsWith('-'));
  final options = parseAnalyzeOptions(args);

  try {
    final snapshot = loadSnapshotFromFile(path);
    final result = analyzeSnapshot(snapshot, options, snapshotLabel: path);
    _emitReport(result, options);
  } on SnapshotLoadException catch (e) {
    stderr.writeln(e.message);
    exit(1);
  }
}

void _emitReport(PerformanceAnalysisResult result, AnalyzeOptions options) {
  switch (options.format) {
    case OutputFormat.json:
      final map = filterJsonBySections(result.toJsonMap(), options.sections);
      print(const JsonEncoder.withIndent('  ').convert(map));
    case OutputFormat.summary:
      printPerformanceSummary(result);
    case OutputFormat.text:
      printPerformanceReport(result, options: options);
  }
}
