import 'dart:async';
import 'dart:io';

const defaultTestConcurrency = 4;
const testSuiteLockPath = '.dart_tool/run_tests.lock';
const defaultHostedUrl = 'https://pub.dev';
const allowPubSourceMismatchEnv = 'RUN_TESTS_ALLOW_PUB_SOURCE_MISMATCH';

/// Matches `url:` lines that describe a hosted package (the `source: hosted`
/// line follows immediately in pubspec.lock format).
final _hostedUrlPattern = RegExp(r'url:\s*"([^"]+)"\s*\n\s*source:\s*hosted');

/// Builds arguments for the project's stable Flutter test entry point.
///
/// By default this runs the non-integration suite and caps concurrency. When
/// a path, name, or other Flutter test option is supplied, it is preserved.
/// Explicit tag and concurrency options take precedence over the defaults.
List<String> buildFlutterTestArgs(List<String> args) {
  return [
    'test',
    if (!_hasExplicitTags(args)) ...['--exclude-tags', 'integration'],
    if (!_hasExplicitConcurrency(args)) '--concurrency=$defaultTestConcurrency',
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

/// Runs [body] while holding an exclusive lock on [lockPath].
///
/// Concurrent invocations queue instead of fighting over the shared
/// `.dart_tool` build state: an async chain serializes callers within the
/// process, and an OS-level advisory lock arbitrates across processes (the
/// OS releases it automatically if a holder dies).
Future<T> withTestSuiteLock<T>(
  String lockPath,
  Future<T> Function() body, {
  void Function()? onWaitStart,
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
      onWaitStart?.call();
    }
    await previousCompleter.future;
    final raf = await _acquireOsLock(key, onWaitStart);
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

Future<RandomAccessFile> _acquireOsLock(
  String lockPath,
  void Function()? onWaitStart,
) async {
  final lockFile = File(lockPath);
  await lockFile.parent.create(recursive: true);
  final raf = await lockFile.open(mode: FileMode.writeOnlyAppend);
  var notified = false;
  while (true) {
    try {
      await raf.lock(FileLock.exclusive);
      return raf;
    } on FileSystemException {
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
    lockedUrl:
        lockFile.existsSync() ? firstHostedUrl(await lockFile.readAsString()) : null,
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
  exitCode = await withTestSuiteLock(
    testSuiteLockPath,
    () async {
      final process = await Process.start(
        Platform.isWindows ? 'flutter.bat' : 'flutter',
        buildFlutterTestArgs(args),
        mode: ProcessStartMode.inheritStdio,
      );
      return process.exitCode;
    },
    onWaitStart: () {
      stderr.writeln(
        'Another run_tests.dart invocation holds the test-suite lock; '
        'waiting for it to finish…',
      );
    },
  );
}
