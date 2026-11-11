import 'dart:io';

import 'test_run_store.dart';

/// Read-only view of recorded test runs.
///
/// Runs alongside `run_tests.dart` without taking the test-suite lock, so an
/// agent can see that a full suite is already in progress and follow its log
/// instead of queueing a duplicate run.
///
/// Usage:
///   dart run tool/test_status.dart                 # recent runs
///   dart run tool/test_status.dart --tail [id]     # follow a run's log
///   dart run tool/test_status.dart --wait-for ID   # wait, then return its code
///   dart run tool/test_status.dart --limit 20
Future<void> main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    _printUsage();
    return;
  }

  final store = TestRunStore.atDefaultLocation(
    Platform.environment[runDirEnv],
  );

  final tailIndex = args.indexOf('--tail');
  if (tailIndex != -1) {
    final next = tailIndex + 1 < args.length ? args[tailIndex + 1] : null;
    final id = (next != null && !next.startsWith('-'))
        ? next
        : await store.currentId();
    if (id == null) {
      stderr.writeln('No recorded runs yet.');
      exitCode = 1;
      return;
    }
    exitCode = await _tail(store, id);
    return;
  }

  final waitIndex = args.indexOf('--wait-for');
  if (waitIndex != -1) {
    if (waitIndex + 1 >= args.length) {
      stderr.writeln('--wait-for requires a run id.');
      exitCode = 2;
      return;
    }
    exitCode = await _waitFor(store, args[waitIndex + 1]);
    return;
  }

  exitCode = await _list(store, _limit(args));
}

int _limit(List<String> args) {
  final index = args.indexOf('--limit');
  if (index != -1 && index + 1 < args.length) {
    return int.tryParse(args[index + 1]) ?? 10;
  }
  return 10;
}

Future<int> _list(TestRunStore store, int limit) async {
  final records = await store.recentRuns(limit: limit);
  if (records.isEmpty) {
    stdout.writeln('No recorded runs under ${store.root.path}.');
    return 0;
  }
  final current = await store.currentRunning();
  stdout.writeln('Recent test runs (showing ${records.length}, newest first):');
  for (final record in records) {
    final marker = current != null && current.id == record.id ? '*' : ' ';
    final when = record.endedAt != null
        ? _ago(record.endedAt)
        : 'running ${_ago(record.startedAt)}';
    final head = record.headSha.isEmpty ? '?' : _short(record.headSha);
    final state = record.headSha.isEmpty
        ? 'unknown'
        : (record.treeDirty ? 'dirty' : 'clean');
    stdout.writeln(
      '$marker ${record.id}  ${record.scope.padRight(11)} '
      '${record.status.name.padRight(8)} $when  '
      'HEAD $head $state',
    );
    stdout.writeln('    ${record.logPath}');
  }
  stdout.writeln(
    '\n* = currently running. '
    '`--tail [id]` follows a log, `--wait-for <id>` waits for completion.',
  );
  return 0;
}

Future<int> _tail(TestRunStore store, String id) async {
  final record = await store.recordById(id);
  if (record == null) {
    stderr.writeln('No such run: $id');
    return 1;
  }
  final log = File(record.logPath);
  var offset = 0;
  while (true) {
    offset = await _drain(log, offset);
    final latest = await store.recordById(id);
    if (latest == null || latest.status != TestRunStatus.running) {
      await _drain(log, offset);
      return 0;
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
}

Future<int> _drain(File log, int offset) async {
  if (!log.existsSync()) return offset;
  final bytes = await log.readAsBytes();
  if (bytes.length > offset) {
    stdout.add(bytes.sublist(offset));
  }
  return bytes.length;
}

Future<int> _waitFor(TestRunStore store, String id) async {
  while (true) {
    final record = await store.recordById(id);
    if (record == null) {
      stderr.writeln('No such run: $id');
      return 1;
    }
    if (record.status != TestRunStatus.running) {
      stdout.writeln(
        'Run $id finished: ${record.status.name} '
        '(exit ${record.exitCode ?? '-'})',
      );
      return record.exitCode ??
          (record.status == TestRunStatus.passed ? 0 : 1);
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
}

String _ago(DateTime? at) {
  if (at == null) return 'unknown';
  final delta = DateTime.now().difference(at);
  if (delta.inSeconds < 60) return '${delta.inSeconds}s ago';
  if (delta.inMinutes < 60) return '${delta.inMinutes}m ago';
  if (delta.inHours < 24) return '${delta.inHours}h ago';
  return '${delta.inDays}d ago';
}

String _short(String sha) => sha.length > 8 ? sha.substring(0, 8) : sha;

void _printUsage() {
  stdout.writeln(
    'Usage: dart run tool/test_status.dart [options]\n'
    '\n'
    '  (no args)          List recent runs (newest first).\n'
    '  --tail [id]        Follow a run log (defaults to the current run).\n'
    '  --wait-for <id>    Wait until a run finishes; exit with its code.\n'
    '  --limit <n>        Number of runs to list (default 10).\n'
    '  -h, --help         Show this help.',
  );
}
