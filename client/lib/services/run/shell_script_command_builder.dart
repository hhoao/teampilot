import '../host/host_interactive_shell.dart';
import 'shell_script_configuration.dart';
import 'shell_script_migrator.dart';

/// Assembles terminal inject lines and non-terminal process invocations.
class ShellScriptCommandBuilder {
  const ShellScriptCommandBuilder();

  /// Single line for terminal inject (ends without CR; caller adds `\r`).
  String buildInjectLine(ShellScriptConfiguration config) {
    final parts = <String>[];

    final cwd = config.cwd?.trim();
    if (cwd != null && cwd.isNotEmpty) {
      parts.add('cd ${_quote(cwd)}');
    }

    for (final entry in config.env.entries) {
      parts.add('export ${_quote(entry.key)}=${_quote(entry.value)}');
    }
    parts.add(_buildInterpreterInvocation(config));

    return parts.join(' && ');
  }

  /// For non-terminal [ProcessRunExecutor]: host shell `-c` with the inject line.
  ShellScriptProcessInvocation buildProcessInvocation(
    ShellScriptConfiguration config,
  ) {
    final fullLine = buildInjectLine(config);
    return ShellScriptProcessInvocation(
      command: HostInteractiveShell.defaultExecutable(),
      args: ['-c', fullLine],
      shell: true,
      cwd: config.cwd,
      env: config.env,
    );
  }

  String _buildInterpreterInvocation(ShellScriptConfiguration config) {
    final tokens = <String>[_quote(config.interpreterPath)];
    final interpreterOptions = config.interpreterOptions.trim();
    if (interpreterOptions.isNotEmpty) {
      tokens.add(interpreterOptions);
    }

    if (config.isScriptText) {
      tokens.add('-c');
      tokens.add(_quote(config.scriptText ?? ''));
    } else {
      tokens.add(_quote(config.scriptPath ?? ''));
    }

    final scriptOptions = config.scriptOptions.trim();
    if (scriptOptions.isNotEmpty) {
      tokens.add(scriptOptions);
    }
    return tokens.join(' ');
  }

  static String _quote(String value) => ShellScriptMigrator.posixShellQuote(value);
}

/// Non-terminal process invocation for [ProcessRunExecutor].
class ShellScriptProcessInvocation {
  const ShellScriptProcessInvocation({
    required this.command,
    required this.args,
    required this.shell,
    required this.cwd,
    required this.env,
  });

  final String command;
  final List<String> args;
  final bool shell;
  final String? cwd;
  final Map<String, String> env;
}
