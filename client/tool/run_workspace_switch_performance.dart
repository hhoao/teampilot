// ignore_for_file: avoid_print
//
// Runs the workspace-switch performance integration test, then analyzes the
// captured DevTools-compatible JSON snapshot.
//
// Usage (from `client/`):
//   dart run tool/run_workspace_switch_performance.dart
//   dart run tool/run_workspace_switch_performance.dart --output /tmp/perf.json

import 'dart:io';

import 'performance_snapshot/analyzer.dart';
import 'performance_snapshot/options.dart';
import 'performance_snapshot/report_summary.dart';
import 'performance_snapshot/snapshot_loader.dart';

Future<void> main(List<String> args) async {
  final output = _readArg(args, '--output') ?? 'build/perf_workspace_switch.json';
  final clientDir = _clientDirectory();

  print('Running workspace switch performance scenario…');
  final testRun = await Process.run(
    'flutter',
    [
      'test',
      'integration_test/workspace_switch_performance_test.dart',
      '--tags',
      'performance',
      '--dart-define=PERF_OUTPUT=$output',
    ],
    workingDirectory: clientDir.path,
    runInShell: true,
  );
  stdout.write(testRun.stdout);
  stderr.write(testRun.stderr);
  if (testRun.exitCode != 0) {
    exit(testRun.exitCode);
  }

  final snapshotPath = File('${clientDir.path}/$output');
  if (!snapshotPath.existsSync()) {
    stderr.writeln('Expected snapshot at ${snapshotPath.path}');
    exit(1);
  }

  print('\n=== Performance analysis (${snapshotPath.path}) ===\n');
  try {
    final snapshot = loadSnapshotFromFile(snapshotPath.path);
    final options = const AnalyzeOptions(format: OutputFormat.summary);
    final result = analyzeSnapshot(
      snapshot,
      options,
      snapshotLabel: snapshotPath.path,
    );
    printPerformanceSummary(result);
  } on SnapshotLoadException catch (e) {
    stderr.writeln(e.message);
    exit(1);
  }
}

Directory _clientDirectory() {
  final cwd = Directory.current;
  if (File('${cwd.path}/pubspec.yaml').existsSync() &&
      File('${cwd.path}/tool/analyze_performance_json.dart').existsSync()) {
    return cwd;
  }
  final nested = Directory('${cwd.path}/client');
  if (File('${nested.path}/pubspec.yaml').existsSync()) {
    return nested;
  }
  throw StateError('Run from repository root or client/');
}

String? _readArg(List<String> args, String name) {
  final i = args.indexOf(name);
  if (i < 0 || i + 1 >= args.length) return null;
  return args[i + 1];
}
