import 'dart:async';
import 'dart:io';

import 'test_run_store.dart';

const defaultTestConcurrency = 4;
const testConcurrencyEnv = 'RUN_TESTS_CONCURRENCY';
const testSuiteLockPath = '.dart_tool/run_tests.lock';
const defaultHostedUrl = 'https://pub.dev';
const allowPubSourceMismatchEnv = 'RUN_TESTS_ALLOW_PUB_SOURCE_MISMATCH';

/// Exit code used by `--no-wait` when another run already holds the suite lock
/// (EX_TEMPFAIL from sysexits.h: "try again later").
const int testSuiteLockedExitCode = 75;

/// Matches `url:` lines that describe a hosted package (the `source: hosted`
/// line follows immediately in pubspec.lock format).
final _hostedUrlPattern = RegExp(r'url:\s*"([^"]+)"\s*\n\s*source:\s*hosted');

/// Builds arguments for the project's stable Flutter test entry point.
///
/// By default this runs the non-integration suite and caps concurrency. When
/// a path, name, or other Flutter test option is supplied, it is preserved.
/// Explicit tag and concurrency options take precedence over the defaults.
/// `RUN_TESTS_CONCURRENCY` overrides the default cap for machine-idle runs
/// (the cap exists to bound widget-settle flakiness, not memory).
List<String> buildFlutterTestArgs(
  List<String> args, {
  String? concurrencyOverride,
}) {
  final effectiveConcurrency = concurrencyOverride ?? '$defaultTestConcurrency';
  return [
    'test',
    if (!_hasExplicitTags(args)) ...['--exclude-tags', 'integration'],
    if (!_hasExplicitConcurrency(args)) '--concurrency=$effectiveConcurrency',
    ...args,
  ];
}

bool _hasExplicitTags(List<String> args) {
  return args.any(
    (arg) =>
        arg == '-t' ||
        arg == '--tags' ||
        arg == '-x' ||
        arg == '--exclude-tags' ||
        arg.startsWith('--tags=') ||
        arg.startsWith('--exclude-tags='),
  );
}

bool _hasExplicitConcurrency(List<String> args) {
  for (final arg in args) {
    if (arg == '-j' || arg == '--concurrency') return true;
    if (arg.startsWith('-j') && arg.length > 2) return true;
    if (arg.startsWith('--concurrency=')) return true;
  }
  return false;
}

/// In-process wait chains keyed by absolute lock path. dart:io file locks
/// are fcntl-based on POSIX and therefore per-process: they only arbitrate
/// across processes, so in-process callers need this queue as well.
final Map<String, Completer<void>> _inProcessSuites = {};

/// Thrown by [withTestSuiteLock] when `wait: false` is requested and the lock
/// is already held. Lets `--no-wait` back off and observe instead of blocking.
class TestSuiteLockUnavailable implements Exception {
  const TestSuiteLockUnavailable();
}

/// Runs [body] while holding an exclusive lock on [lockPath].
///
/// Concurrent invocations queue instead of fighting over the shared
/// `.dart_tool` build state: an async chain serializes callers within the
/// process, and an OS-level advisory lock arbitrates across processes (the
/// OS releases it automatically if a holder dies). With [wait] false, the call
/// throws [TestSuiteLockUnavailable] instead of queueing.
Future<T> withTestSuiteLock<T>(
  String lockPath,
  Future<T> Function() body, {
  void Function()? onWaitStart,
  bool wait = true,
}) {
  final key = File(lockPath).absolute.path;
  final previousCompleter = _inProcessSuites.putIfAbsent(key, () {
    final ready = Completer<void>();
    ready.complete();
    return ready;
  });
  final done = Completer<void>();
  _inProcessSuites[key] = done;

  return () async {
    if (!previousCompleter.isCompleted) {
      if (!wait) {
        _inProcessSuites[key] = previousCompleter;
        throw const TestSuiteLockUnavailable();
      }
      onWaitStart?.call();
    }
    await previousCompleter.future;
    final raf = await _acquireOsLock(key, onWaitStart, wait: wait);
    if (raf == null) {
      throw const TestSuiteLockUnavailable();
    }
    try {
      return await body();
    } finally {
      try {
        await raf.unlock();
      } finally {
        await raf.close();
      }
    }
  }().whenComplete(done.complete);
}

Future<RandomAccessFile?> _acquireOsLock(
  String lockPath,
  void Function()? onWaitStart, {
  bool wait = true,
}) async {
  final lockFile = File(lockPath);
  await lockFile.parent.create(recursive: true);
  final raf = await lockFile.open(mode: FileMode.writeOnlyAppend);
  var notified = false;
  while (true) {
    try {
      await raf.lock(FileLock.exclusive);
      return raf;
    } on FileSystemException {
      if (!wait) {
        await raf.close();
        return null;
      }
      if (!notified) {
        notified = true;
        onWaitStart?.call();
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }
}

/// Extracts the hosted URL of the first hosted package in a pubspec.lock, or
/// null when nothing is hosted (path/sdk-only locks skip the source check).
String? firstHostedUrl(String lockContents) {
  return _hostedUrlPattern.firstMatch(lockContents)?.group(1);
}

/// Normalizes a hosted URL for comparison (trims and drops trailing slash).
String normalizeHostedUrl(String url) {
  final trimmed = url.trim();
  return trimmed.endsWith('/')
      ? trimmed.substring(0, trimmed.length - 1)
      : trimmed;
}

/// Returns remediation guidance when the environment's effective pub source
/// differs from [lockedUrl], or null when they agree (or cannot be compared).
String? pubSourceMismatchMessage({
  required String? lockedUrl,
  required String? effectiveSource,
}) {
  if (lockedUrl == null || effectiveSource == null) return null;
  if (normalizeHostedUrl(lockedUrl) == normalizeHostedUrl(effectiveSource)) {
    return null;
  }
  return 'pubspec.lock was resolved against "$lockedUrl" but this environment '
      'resolves packages from "$effectiveSource" (PUB_HOSTED_URL); running '
      'pub get now would rewrite the lockfile. Align PUB_HOSTED_URL with the '
      'lockfile, or set $allowPubSourceMismatchEnv=1 to proceed anyway.';
}

Future<void> main(List<String> args) async {
  final env = Platform.environment;
  final lockFile = File('pubspec.lock');
  final mismatch = pubSourceMismatchMessage(
    lockedUrl: lockFile.existsSync()
        ? firstHostedUrl(await lockFile.readAsString())
        : null,
    effectiveSource: env['PUB_HOSTED_URL'] ?? defaultHostedUrl,
  );
  if (mismatch != null) {
    final allowed = env[allowPubSourceMismatchEnv] == '1';
    stderr.writeln('${allowed ? 'warning' : 'error'}: $mismatch');
    if (!allowed) {
      exitCode = 1;
      return;
    }
  }

  var reuse = false;
  var noWait = false;
  final flutterArgs = <String>[];
  for (final arg in args) {
    if (arg == '--reuse') {
      reuse = true;
    } else if (arg == '--no-wait') {
      noWait = true;
    } else {
      flutterArgs.add(arg);
    }
  }

  final store = TestRunStore.atDefaultLocation(env[runDirEnv]);
  final scope = classifyScope(flutterArgs);
  final selectionKey = selectionKeyFor(flutterArgs);
  final maxAge = _reuseMaxAge(env);

  try {
    exitCode = await withTestSuiteLock(
      testSuiteLockPath,
      () async {
        final snapshot = scope == 'full'
            ? await describeWorkspace()
            : WorkspaceSnapshot.unknown;
        if (reuse && scope == 'full' && !snapshot.treeDirty) {
          final candidates = await store.recentRuns(limit: 500);
          final hit = store.findReusable(
            candidates: candidates,
            selectionKey: selectionKey,
            headSha: snapshot.headSha,
            lockHash: snapshot.lockHash,
            now: DateTime.now(),
            maxAge: maxAge,
          );
          if (hit != null) {
            stdout.writeln(
              'Reusing green full-suite run ${hit.id} '
              '(finished ${_ago(hit.endedAt)}, HEAD ${_short(snapshot.headSha)}); '
              'skipping execution. Workspace unchanged since that run.',
            );
            await store.markReused(hit);
            return 0;
          }
        }
        await store.prune();
        final record = await store.startRun(
          args: flutterArgs,
          selectionKey: selectionKey,
          scope: scope,
          headSha: snapshot.headSha,
          treeDirty: snapshot.treeDirty,
          lockHash: snapshot.lockHash,
        );
        var code = 1;
        try {
          code = await _runFlutterTest(flutterArgs, logPath: record.logPath);
        } catch (_) {
          await store.finishRun(record.id, status: TestRunStatus.error);
          rethrow;
        }
        await store.finishRun(
          record.id,
          status: code == 0 ? TestRunStatus.passed : TestRunStatus.failed,
          exitCode: code,
        );
        return code;
      },
      wait: !noWait,
      onWaitStart: () {
        stderr.writeln(
          'Another run_tests.dart invocation holds the test-suite lock; '
          'waiting for it to finish…',
        );
        unawaited(_reportActiveRun(store));
      },
    );
  } on TestSuiteLockUnavailable {
    stdout.writeln(
      'Another run_tests.dart invocation holds the test-suite lock; '
      'not waiting (--no-wait).',
    );
    final active = await store.currentRunning();
    if (active != null) {
      stdout.writeln(
        '  in progress: ${active.id} scope=${active.scope} '
        'started ${_ago(active.startedAt)}',
      );
      stdout.writeln('  view log:   dart run tool/test_status.dart --tail');
    } else {
      stdout.writeln('  view runs:  dart run tool/test_status.dart');
    }
    exitCode = testSuiteLockedExitCode;
  }
}

Duration _reuseMaxAge(Map<String, String> env) {
  final minutes = int.tryParse(env[reuseMaxAgeEnv] ?? '');
  return Duration(minutes: minutes ?? defaultReuseMaxAgeMinutes);
}

Future<void> _reportActiveRun(TestRunStore store) async {
  try {
    final active = await store.currentRunning();
    if (active == null) return;
    stderr.writeln(
      '  in progress: ${active.id} scope=${active.scope} '
      'started ${_ago(active.startedAt)}',
    );
    stderr.writeln('  view log:   dart run tool/test_status.dart --tail');
  } catch (_) {
    // Best-effort diagnostics only.
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

/// Captures the bits of workspace state that decide whether a previous green
/// full run still applies: the commit, whether the tree is dirty, and the
/// pubspec.lock content hash. Any failure yields [WorkspaceSnapshot.unknown],
/// whose `treeDirty: true` disables reuse (never mis-reuse on unknown state).
class WorkspaceSnapshot {
  const WorkspaceSnapshot({
    required this.headSha,
    required this.treeDirty,
    required this.lockHash,
  });

  final String headSha;
  final bool treeDirty;
  final String lockHash;

  static const WorkspaceSnapshot unknown = WorkspaceSnapshot(
    headSha: '',
    treeDirty: true,
    lockHash: '',
  );
}

Future<WorkspaceSnapshot> describeWorkspace() async {
  try {
    final head = (await _git(['rev-parse', 'HEAD'])).trim();
    final status = (await _git(['status', '--porcelain', '--', '.'])).trim();
    final lockHash = (await _git(['hash-object', 'pubspec.lock'])).trim();
    return WorkspaceSnapshot(
      headSha: head,
      treeDirty: status.isNotEmpty,
      lockHash: lockHash,
    );
  } catch (_) {
    return WorkspaceSnapshot.unknown;
  }
}

Future<String> _git(List<String> args) async {
  final result = await Process.run('git', args);
  if (result.exitCode != 0) {
    throw ProcessException(
      'git',
      args,
      result.stderr.toString(),
      result.exitCode,
    );
  }
  return result.stdout as String;
}

/// Runs `flutter test` while teeing stdout/stderr to the terminal and to
/// [logPath] so other agents can follow the run without holding the lock.
Future<int> _runFlutterTest(
  List<String> flutterArgs, {
  required String logPath,
}) async {
  final process = await Process.start(
    Platform.isWindows ? 'flutter.bat' : 'flutter',
    buildFlutterTestArgs(
      flutterArgs,
      concurrencyOverride: Platform.environment[testConcurrencyEnv],
    ),
    mode: ProcessStartMode.normal,
  );
  IOSink? logSink;
  try {
    logSink = File(logPath).openWrite();
  } catch (_) {
    logSink = null;
  }
  final outDone = process.stdout
      .listen((data) {
        stdout.add(data);
        logSink?.add(data);
      })
      .asFuture<void>();
  final errDone = process.stderr
      .listen((data) {
        stderr.add(data);
        logSink?.add(data);
      })
      .asFuture<void>();
  final code = await process.exitCode;
  await Future.wait<void>([outDone, errDone]);
  if (logSink != null) {
    await logSink.flush();
    await logSink.close();
  }
  return code;
}
