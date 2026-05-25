import 'cli_tool_locator.dart';

/// Backward-compatible facade for resolving the `flashskyai` CLI executable.
class FlashskyaiCliLocator {
  const FlashskyaiCliLocator._();

  static const _locator = CliToolLocator('flashskyai');

  /// Shell command used to resolve `flashskyai` on PATH (local or remote).
  static const lookupCommand = 'command -v flashskyai';

  static Future<String?> locate({
    ProcessRunner runner = cliToolDefaultProcessRun,
  }) {
    return _locator.locate(runner: runner);
  }

  static String? parseFirstStdoutLine(Object? stdoutValue) {
    return CliToolLocator.parseFirstStdoutLine(stdoutValue);
  }
}
