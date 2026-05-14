import 'dart:convert';
import 'dart:io';

/// On Windows, if [path] looks like a WSL-side POSIX absolute path (`/home/...`),
/// converts it with `wslpath -w` so `dart:io` [File] can open it.
///
/// Returns [path] unchanged when not Windows, when [path] is not POSIX-absolute,
/// or when `wslpath` fails.
Future<String> windowsFilePathForPossibleWslPosixPath(String path) async {
  if (!Platform.isWindows) return path;
  final trimmed = path.trim();
  if (trimmed.isEmpty || !trimmed.startsWith('/')) return path;
  if (trimmed.startsWith('//')) return path;
  try {
    final result = await Process.run(
      'wsl.exe',
      ['wslpath', '-w', trimmed],
      stdoutEncoding: latin1,
      stderrEncoding: latin1,
    );
    if (result.exitCode != 0) return path;
    final out = result.stdout;
    final text = out is String
        ? out
        : latin1.decode(out as List<int>, allowInvalid: true);
    final line = text
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty, orElse: () => '');
    if (line.isEmpty) return path;
    return line;
  } on Object {
    return path;
  }
}
