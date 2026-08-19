import 'dart:io';

const defaultTestConcurrency = 4;

/// Builds arguments for the project's stable Flutter test entry point.
///
/// With no arguments this runs the default non-integration suite. When a
/// path, name, tag, or other Flutter test option is supplied, it is preserved
/// and only the safe concurrency cap is added when the caller did not choose
/// one explicitly.
List<String> buildFlutterTestArgs(List<String> args) {
  if (args.isEmpty) {
    return [
      'test',
      '--exclude-tags',
      'integration',
      '--concurrency=$defaultTestConcurrency',
    ];
  }

  return [
    'test',
    if (!_hasExplicitConcurrency(args)) '--concurrency=$defaultTestConcurrency',
    ...args,
  ];
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
