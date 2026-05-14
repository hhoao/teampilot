import 'dart:io';

typedef ProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

/// Resolves the absolute path of the `flashskyai` CLI executable on PATH.
/// Returns null when not installed or the lookup fails.
class FlashskyaiCliLocator {
  const FlashskyaiCliLocator._();

  static Future<String?> locate({ProcessRunner runner = Process.run}) async {
    final cmd = Platform.isWindows ? 'where' : 'which';
    try {
      final result = await runner(cmd, ['flashskyai']);
      if (result.exitCode == 0) {
        final located = _firstStdoutLine(result.stdout);
        if (located != null) return located;
      }
      if (Platform.isWindows) {
        return _locateInWsl(runner);
      }
      return null;
    } on ProcessException {
      if (Platform.isWindows) {
        return _locateInWsl(runner);
      }
      return null;
    } on Object {
      return null;
    }
  }

  static Future<String?> _locateInWsl(ProcessRunner runner) async {
    try {
      final result = await runner('wsl.exe', [
        'sh',
        '-lc',
        'command -v flashskyai',
      ]);
      if (result.exitCode != 0) return null;
      final located = _firstStdoutLine(result.stdout);
      if (located == null) return null;
      return 'wsl.exe $located';
    } on Object {
      return null;
    }
  }

  static String? _firstStdoutLine(Object? stdoutValue) {
    if (stdoutValue is! String) return null;
    final firstLine = stdoutValue
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty, orElse: () => '');
    if (firstLine.isEmpty) return null;
    return firstLine;
  }
}
