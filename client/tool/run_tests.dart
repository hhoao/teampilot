import 'dart:io';

const defaultTestConcurrency = 4;

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

Future<void> main(List<String> args) async {
  final process = await Process.start(
    Platform.isWindows ? 'flutter.bat' : 'flutter',
    buildFlutterTestArgs(args),
    mode: ProcessStartMode.inheritStdio,
  );
  exitCode = await process.exitCode;
}
