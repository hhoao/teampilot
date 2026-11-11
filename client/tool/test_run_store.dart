import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Directory (relative to `client/`) where per-run records and logs live.
///
/// `.dart_tool/` is gitignored, so this is a shared, machine-local area that
/// every agent working in the same checkout can read without taking the
/// test-suite lock. Override with the [runDirEnv] environment variable.
const String defaultRunDir = '.dart_tool/test_runs';
const String runDirEnv = 'RUN_TESTS_DIR';

/// Freshness window for [TestRunStore.findReusable]; see
/// [defaultReuseMaxAgeMinutes]. Override with [reuseMaxAgeEnv].
const String reuseMaxAgeEnv = 'RUN_TESTS_REUSE_MAX_AGE_MINUTES';
const int defaultReuseMaxAgeMinutes = 30;

final Random _random = Random();

/// Canonical key for a test selection. Reuse requires byte-identical args, so
/// the same effective selection invoked with different formatting simply
/// re-runs instead of risking a false hit.
String selectionKeyFor(List<String> flutterArgs) => flutterArgs.join('\u0000');

/// Classifies a run so `test_status` can label it and reuse can stay narrow.
///
/// Only an argument-free invocation — the default non-integration suite — is
/// eligible for reuse. Any selector (path, `--plain-name`, `--tags`, …) makes
/// the run "scoped"/"integration" and is never reused, which keeps the safety
/// argument simple.
String classifyScope(List<String> flutterArgs) {
  if (flutterArgs.isEmpty) return 'full';
  final tagged = flutterArgs.any(
    (a) => a == '-t' || a == '--tags' || a.startsWith('--tags='),
  );
  return tagged ? 'integration' : 'scoped';
}

enum TestRunStatus { running, passed, failed, error, reused, crashed }

TestRunStatus parseTestRunStatus(Object? value) {
  final name = value?.toString();
  for (final status in TestRunStatus.values) {
    if (status.name == name) return status;
  }
  return TestRunStatus.error;
}

/// One recorded test invocation. Serialized as `<id>.json` next to the log.
class TestRunRecord {
  const TestRunRecord({
    required this.id,
    required this.pid,
    required this.host,
    required this.args,
    required this.selectionKey,
    required this.scope,
    required this.headSha,
    required this.treeDirty,
    required this.lockHash,
    required this.startedAt,
    required this.endedAt,
    required this.status,
    required this.exitCode,
    required this.logPath,
  });

  final String id;
  final int pid;
  final String host;
  final List<String> args;
  final String selectionKey;

  /// `full`, `scoped`, or `integration`.
  final String scope;

  /// `git rev-parse HEAD` when the run started, or `''` when not captured.
  final String headSha;

  /// Whether `git status --porcelain` reported changes when the run started.
  final bool treeDirty;

  /// `git hash-object pubspec.lock` for the lockfile in effect.
  final String lockHash;

  final DateTime startedAt;
  final DateTime? endedAt;
  final TestRunStatus status;
  final int? exitCode;
  final String logPath;

  TestRunRecord copyWith({
    TestRunStatus? status,
    int? exitCode,
    DateTime? endedAt,
  }) {
    return TestRunRecord(
      id: id,
      pid: pid,
      host: host,
      args: args,
      selectionKey: selectionKey,
      scope: scope,
      headSha: headSha,
      treeDirty: treeDirty,
      lockHash: lockHash,
      startedAt: startedAt,
      endedAt: endedAt ?? this.endedAt,
      status: status ?? this.status,
      exitCode: exitCode ?? this.exitCode,
      logPath: logPath,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'pid': pid,
    'host': host,
    'args': args,
    'selectionKey': selectionKey,
    'scope': scope,
    'headSha': headSha,
    'treeDirty': treeDirty,
    'lockHash': lockHash,
    'startedAt': startedAt.toIso8601String(),
    'endedAt': endedAt?.toIso8601String(),
    'status': status.name,
    'exitCode': exitCode,
    'logPath': logPath,
  };

  factory TestRunRecord.fromJson(Map<String, dynamic> json) {
    final ended = json['endedAt'];
    return TestRunRecord(
      id: json['id'] as String,
      pid: (json['pid'] as num?)?.toInt() ?? 0,
      host: (json['host'] as String?) ?? '',
      args: ((json['args'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(growable: false),
      selectionKey: (json['selectionKey'] as String?) ?? '',
      scope: (json['scope'] as String?) ?? 'scoped',
      headSha: (json['headSha'] as String?) ?? '',
      treeDirty: (json['treeDirty'] as bool?) ?? true,
      lockHash: (json['lockHash'] as String?) ?? '',
      startedAt: DateTime.parse(json['startedAt'] as String),
      endedAt: ended == null ? null : DateTime.parse(ended as String),
      status: parseTestRunStatus(json['status']),
      exitCode: (json['exitCode'] as num?)?.toInt(),
      logPath: (json['logPath'] as String?) ?? '',
    );
  }
}

/// Reads and writes run records under [root]. Deliberately has no knowledge of
/// git or flutter: callers capture the workspace snapshot and pass it in.
class TestRunStore {
  TestRunStore(this.root);

  TestRunStore.atDefaultLocation([String? override])
    : root = Directory(override ?? defaultRunDir);

  final Directory root;

  static const String _currentName = 'current';

  File recordFile(String id) => File('${root.path}/$id.json');
  File logFile(String id) => File('${root.path}/$id.log');
  File get currentFile => File('${root.path}/$_currentName');

  Future<void> ensureReady() async {
    if (!root.existsSync()) {
      await root.create(recursive: true);
    }
  }

  Future<TestRunRecord> startRun({
    required List<String> args,
    required String selectionKey,
    required String scope,
    required String headSha,
    required bool treeDirty,
    required String lockHash,
    DateTime? now,
  }) async {
    await ensureReady();
    final startedAt = now ?? DateTime.now();
    final id = _newId(startedAt);
    final record = TestRunRecord(
      id: id,
      pid: pid,
      host: _safeHostname(),
      args: List<String>.unmodifiable(args),
      selectionKey: selectionKey,
      scope: scope,
      headSha: headSha,
      treeDirty: treeDirty,
      lockHash: lockHash,
      startedAt: startedAt,
      endedAt: null,
      status: TestRunStatus.running,
      exitCode: null,
      logPath: logFile(id).path,
    );
    await save(record);
    await markCurrent(id);
    return record;
  }

  /// Records that [source] was reused instead of executed.
  Future<void> markReused(TestRunRecord source, {DateTime? now}) async {
    await ensureReady();
    final at = now ?? DateTime.now();
    final id = _newId(at);
    await save(
      TestRunRecord(
        id: id,
        pid: pid,
        host: _safeHostname(),
        args: source.args,
        selectionKey: source.selectionKey,
        scope: source.scope,
        headSha: source.headSha,
        treeDirty: false,
        lockHash: source.lockHash,
        startedAt: at,
        endedAt: at,
        status: TestRunStatus.reused,
        exitCode: 0,
        logPath: logFile(id).path,
      ),
    );
    await markCurrent(id);
  }

  /// Writes [record] atomically (temp file + rename) so a concurrent reader
  /// never observes a half-written JSON document.
  Future<void> save(TestRunRecord record) async {
    await ensureReady();
    final target = recordFile(record.id);
    final tmp = File('${target.path}.tmp');
    await tmp.writeAsString(
      const JsonEncoder.withIndent('  ').convert(record.toJson()),
      flush: true,
    );
    await tmp.rename(target.path);
  }

  Future<void> finishRun(
    String id, {
    required TestRunStatus status,
    int? exitCode,
    DateTime? now,
  }) async {
    final record = await recordById(id);
    if (record == null) return;
    await save(
      record.copyWith(
        status: status,
        exitCode: exitCode,
        endedAt: now ?? DateTime.now(),
      ),
    );
  }

  Future<void> markCurrent(String id) async {
    await ensureReady();
    await currentFile.writeAsString(id, flush: true);
  }

  Future<String?> currentId() async {
    if (!currentFile.existsSync()) return null;
    final value = (await currentFile.readAsString()).trim();
    return value.isEmpty ? null : value;
  }

  Future<TestRunRecord?> recordById(String id) async {
    final file = recordFile(id);
    if (!file.existsSync()) return null;
    try {
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return TestRunRecord.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  Future<TestRunRecord?> currentRunning() async {
    final id = await currentId();
    if (id == null) return null;
    final record = await recordById(id);
    if (record == null || record.status != TestRunStatus.running) return null;
    return record;
  }

  Future<List<TestRunRecord>> recentRuns({int limit = 20}) async {
    if (!root.existsSync()) return const [];
    final records = <TestRunRecord>[];
    await for (final entity in root.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final json =
            jsonDecode(await entity.readAsString()) as Map<String, dynamic>;
        records.add(TestRunRecord.fromJson(json));
      } catch (_) {
        // Ignore corrupt or partially-written records.
      }
    }
    records.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    if (limit <= 0 || records.length <= limit) return records;
    return records.sublist(0, limit);
  }

  /// Returns the newest green `full` run that proves the current clean HEAD +
  /// lockfile were already tested, or null. Reuse is intentionally narrow: any
  /// dirty, failed, scoped, or mismatched run is ignored.
  TestRunRecord? findReusable({
    required List<TestRunRecord> candidates,
    required String selectionKey,
    required String headSha,
    required String lockHash,
    required DateTime now,
    Duration maxAge = const Duration(minutes: defaultReuseMaxAgeMinutes),
  }) {
    TestRunRecord? best;
    for (final record in candidates) {
      if (record.status != TestRunStatus.passed) continue;
      if (record.scope != 'full') continue;
      if (record.treeDirty) continue;
      if (record.selectionKey != selectionKey) continue;
      if (headSha.isEmpty || record.headSha != headSha) continue;
      if (record.lockHash != lockHash) continue;
      final ended = record.endedAt;
      if (ended == null) continue;
      final age = now.difference(ended);
      if (age.isNegative || age > maxAge) continue;
      if (best == null || ended.isAfter(best.endedAt!)) best = record;
    }
    return best;
  }

  Future<void> prune({
    DateTime? now,
    Duration maxAge = const Duration(days: 7),
    int keep = 200,
  }) async {
    final records = await recentRuns(limit: 0);
    final cutoff = (now ?? DateTime.now()).subtract(maxAge);
    for (var i = 0; i < records.length; i++) {
      final record = records[i];
      if (record.startedAt.isBefore(cutoff) || i >= keep) {
        try {
          await recordFile(record.id).delete();
        } catch (_) {}
        try {
          await logFile(record.id).delete();
        } catch (_) {}
      }
    }
  }

  String _newId(DateTime at) {
    final suffix = _random.nextInt(0x10000).toRadixString(16).padLeft(4, '0');
    return '${_compactTimestamp(at)}-$pid-$suffix';
  }

  static String _compactTimestamp(DateTime t) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${t.year}${two(t.month)}${two(t.day)}T'
        '${two(t.hour)}${two(t.minute)}${two(t.second)}'
        '${t.millisecond.toString().padLeft(3, '0')}';
  }

  static String _safeHostname() {
    try {
      return Platform.localHostname;
    } catch (_) {
      return 'unknown';
    }
  }
}
