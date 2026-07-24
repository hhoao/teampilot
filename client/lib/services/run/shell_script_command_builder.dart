import '../host/host_interactive_shell.dart';
import '../host/host_interactive_shell_kind.dart';
import 'shell_script_configuration.dart';

/// Assembles terminal inject lines and non-terminal process invocations.
class ShellScriptCommandBuilder {
  const ShellScriptCommandBuilder();

  /// Single line for terminal inject (ends without CR; caller adds `\r`).
  ///
  /// Quoting / `cd` / env syntax follow [config.interpreterPath]'s shell family
  /// so Windows `cmd` / PowerShell configs are not forced through POSIX quotes.
  String buildInjectLine(ShellScriptConfiguration config) {
    final dialect = _dialectFor(config.interpreterPath);
    final parts = <String>[];

    final cwd = config.cwd?.trim();
    if (cwd != null && cwd.isNotEmpty) {
      parts.add(_cdCommand(cwd, dialect));
    }

    for (final entry in config.env.entries) {
      parts.add(_envAssign(entry.key, entry.value, dialect));
    }
    parts.add(_buildInterpreterInvocation(config, dialect));

    return parts.join(' && ');
  }

  /// For non-terminal [ProcessRunExecutor]: host shell command flag with the
  /// inject line.
  ShellScriptProcessInvocation buildProcessInvocation(
    ShellScriptConfiguration config,
  ) {
    final fullLine = buildInjectLine(config);
    final host = HostInteractiveShell.defaultSpec();
    return ShellScriptProcessInvocation(
      command: host.executable,
      args: [_commandFlagFor(host.kind), fullLine],
      shell: true,
      cwd: config.cwd,
      env: config.env,
    );
  }

  String _buildInterpreterInvocation(
    ShellScriptConfiguration config,
    _ShellDialect dialect,
  ) {
    final tokens = <String>[_quote(config.interpreterPath, dialect)];
    final interpreterOptions = config.interpreterOptions.trim();
    if (interpreterOptions.isNotEmpty) {
      tokens.add(interpreterOptions);
    }

    if (config.isScriptText) {
      if (!_optionsAlreadyContainCommandFlag(interpreterOptions, dialect)) {
        tokens.add(_commandFlagForDialect(dialect));
      }
      tokens.add(_quote(config.scriptText ?? '', dialect));
    } else {
      tokens.add(_quote(config.scriptPath ?? '', dialect));
    }

    final scriptOptions = config.scriptOptions.trim();
    if (scriptOptions.isNotEmpty) {
      tokens.add(scriptOptions);
    }
    return tokens.join(' ');
  }

  static _ShellDialect _dialectFor(String interpreterPath) {
    final kind = HostInteractiveShellKind.fromExecutable(interpreterPath);
    return switch (kind) {
      HostInteractiveShellKind.cmd => _ShellDialect.cmd,
      HostInteractiveShellKind.powershell ||
      HostInteractiveShellKind.pwsh => _ShellDialect.powershell,
      _ => _ShellDialect.posix,
    };
  }

  static String _commandFlagFor(HostInteractiveShellKind kind) {
    return switch (kind) {
      HostInteractiveShellKind.cmd => '/c',
      HostInteractiveShellKind.powershell ||
      HostInteractiveShellKind.pwsh => '-Command',
      _ => '-c',
    };
  }

  static String _commandFlagForDialect(_ShellDialect dialect) {
    return switch (dialect) {
      _ShellDialect.cmd => '/c',
      _ShellDialect.powershell => '-Command',
      _ShellDialect.posix => '-c',
    };
  }

  static bool _optionsAlreadyContainCommandFlag(
    String interpreterOptions,
    _ShellDialect dialect,
  ) {
    if (interpreterOptions.isEmpty) return false;
    final tokens = interpreterOptions.split(RegExp(r'\s+'));
    final flag = _commandFlagForDialect(dialect);
    return tokens.any((t) => t.toLowerCase() == flag.toLowerCase());
  }

  static String _cdCommand(String cwd, _ShellDialect dialect) {
    return switch (dialect) {
      // /d allows changing drive letter on Windows.
      _ShellDialect.cmd => 'cd /d ${_quote(cwd, dialect)}',
      _ShellDialect.powershell => 'Set-Location ${_quote(cwd, dialect)}',
      _ShellDialect.posix => 'cd ${_quote(cwd, dialect)}',
    };
  }

  static String _envAssign(String key, String value, _ShellDialect dialect) {
    return switch (dialect) {
      _ShellDialect.cmd => 'set ${_quote('$key=$value', dialect)}',
      _ShellDialect.powershell =>
        '\$env:${_psIdent(key)}=${_quote(value, dialect)}',
      _ShellDialect.posix =>
        'export ${_quote(key, dialect)}=${_quote(value, dialect)}',
    };
  }

  /// POSIX single-quote wrap with `'\''` escape for embedded quotes.
  static String posixShellQuote(String value) =>
      "'${value.replaceAll("'", r"'\''")}'";

  /// cmd.exe double-quote wrap; embedded `"` → `""`.
  static String cmdShellQuote(String value) =>
      '"${value.replaceAll('"', '""')}"';

  /// PowerShell single-quote wrap; embedded `'` → `''`.
  static String powershellQuote(String value) =>
      "'${value.replaceAll("'", "''")}'";

  static String _quote(String value, _ShellDialect dialect) {
    return switch (dialect) {
      _ShellDialect.cmd => cmdShellQuote(value),
      _ShellDialect.powershell => powershellQuote(value),
      _ShellDialect.posix => posixShellQuote(value),
    };
  }

  static String _psIdent(String key) {
    // Keep simple env keys unquoted; unusual keys are still assigned via
    // New-Item semantics only if callers pass a valid identifier.
    return key;
  }
}

enum _ShellDialect { posix, cmd, powershell }

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
