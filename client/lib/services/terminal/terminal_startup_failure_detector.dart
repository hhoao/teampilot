import '../cli/cli_executable_validator.dart';

/// Pure startup-failure heuristics for PTY stderr/stdout during launch.
abstract final class TerminalStartupFailureDetector {
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
}
