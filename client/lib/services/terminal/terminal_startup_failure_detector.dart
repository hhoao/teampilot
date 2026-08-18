import '../cli/cli_executable_validator.dart';

/// Pure startup-failure heuristics for PTY stderr/stdout during launch.
abstract final class TerminalStartupFailureDetector {
  static const codexHookTrustReviewMessage =
      '[Codex 正在等待 Hook 信任确认：检测到新的或已变更的 Hooks。'
      '请在终端选择 “Trust all and continue”（通常按 2），或选择不信任后重试。]';

  static const _maxOutputLength = 8192;

  /// Keeps a bounded normalized PTY window so prompts split across output
  /// chunks can still be recognized after the terminal has entered running.
  static String appendOutput(String previous, String next) {
    final normalized = _normalizeTerminalText('$previous$next');
    if (normalized.length <= _maxOutputLength) return normalized;
    return normalized.substring(normalized.length - _maxOutputLength);
  }

  /// Codex displays this interactive trust screen before it can process the
  /// first user turn. It is not a normal permission hook event and does not
  /// arrive through the agent-status HTTP path.
  static bool looksLikeCodexHookTrustReview(String text) {
    final normalized = _normalizeTerminalText(text);
    return normalized.contains('hooks need review') &&
        normalized.contains('trust all and continue') &&
        normalized.contains('hooks can run outside the sandbox');
  }

  static bool looksLikeExecFailure(String text) {
    return text.contains('execvp:') ||
        text.contains('No such file or directory') ||
        text.contains('没有那个文件或目录');
  }

  /// Claude Code (and similar CLIs) print a fatal config/permission error then
  /// exit 1 — often after the first PTY bytes so confirmation already ran.
  static bool looksLikeCliStartupFailure(String text) {
    return text.contains('matches no known tool') ||
        text.contains('cannot be used with root/sudo privileges') ||
        text.contains('Permission deny rule');
  }

  static String launchFailureMessage(
    String executable, {
    required bool validateLaunch,
  }) {
    final cliName = CliExecutableValidator.cliDisplayName(executable);
    if (!validateLaunch) {
      return '[无法启动远端 $cliName: "$executable"。\n'
          '  请检查 SSH Profile 中的远端路径、PATH、工作目录和执行权限。]';
    }
    return execFailureMessage(executable);
  }

  static String execFailureMessage(String executable) {
    final cliName = CliExecutableValidator.cliDisplayName(executable);
    return CliExecutableValidator.validateLaunch(
          executable: executable,
          workingDirectory: '',
        ) ??
        '[无法启动 $cliName: 未找到可执行文件 "$executable"。\n'
            '  请在「设置 → 会话」中配置 $cliName CLI 的绝对路径，'
            '或确保其已在 PATH 中（从文件管理器启动 AppImage 时 PATH 可能很短）。]';
  }

  static String _normalizeTerminalText(String text) {
    return text
        .replaceAll(RegExp(r'\x1B\][^\x07]*(?:\x07|\x1B\\)'), '')
        .replaceAll(RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .toLowerCase();
  }
}
