import 'dart:io';

/// Resolves the absolute path of the `flashskyai` CLI executable on PATH.
/// Returns null when not installed or the lookup fails.
class FlashskyaiCliLocator {
  const FlashskyaiCliLocator._();

  static Future<String?> locate() async {
    final cmd = Platform.isWindows ? 'where' : 'which';
    try {
      final result = await Process.run(cmd, ['flashskyai']);
      if (result.exitCode != 0) return null;
      final stdout = result.stdout;
      if (stdout is! String) return null;
      final firstLine = stdout
          .split(RegExp(r'\r?\n'))
          .map((l) => l.trim())
          .firstWhere((l) => l.isNotEmpty, orElse: () => '');
      if (firstLine.isEmpty) return null;
      return firstLine;
    } on ProcessException {
      return null;
    } on Object {
      return null;
    }
  }
}
