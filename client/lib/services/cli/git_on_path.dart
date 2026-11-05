import 'dart:io';

/// Mobile never has a usable local git work tree for rewind.
bool isMobilePlatform() => Platform.isAndroid || Platform.isIOS;

/// Whether a `git` executable is on `PATH`.
///
/// Mobile never counts as present. Uses [File.existsSync] so widget tests
/// that gate rewind UI do not spawn a [Process.run] timer.
bool gitOnPath() {
  if (Platform.isAndroid || Platform.isIOS) return false;
  final path = Platform.environment['PATH'] ?? '';
  if (path.isEmpty) return false;
  final separator = Platform.isWindows ? ';' : ':';
  final names = Platform.isWindows
      ? const ['git.exe', 'git.cmd', 'git']
      : const ['git'];
  for (final dir in path.split(separator)) {
    if (dir.isEmpty) continue;
    for (final name in names) {
      final candidate = '$dir${Platform.pathSeparator}$name';
      if (File(candidate).existsSync()) return true;
    }
  }
  return false;
}
