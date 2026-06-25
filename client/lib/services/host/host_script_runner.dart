import '../cli/installer_types.dart';
import 'host_execution_environment.dart';
import 'host_script_dialect.dart';

/// Builds hook command strings and installer argv for [HostExecutionEnvironment].
final class HostScriptRunner {
  const HostScriptRunner(this.environment);

  final HostExecutionEnvironment environment;

  HostScriptDialect get dialect => environment.dialect;

  String hookFileName(String baseName) => '$baseName${dialect.scriptExtension}';

  String escapePath(String path) => switch (dialect) {
    HostScriptDialect.bash => path.replaceAll('"', r'\"'),
    HostScriptDialect.powershell => path.replaceAll('"', '""'),
  };

  /// Claude `settings.json` PreToolUse `command` for [scriptPath].
  String commandStringForScriptFile(String scriptPath) {
    final escaped = escapePath(scriptPath);
    return switch (dialect) {
      HostScriptDialect.bash => 'bash "$escaped"',
      HostScriptDialect.powershell =>
        'powershell -NoProfile -ExecutionPolicy Bypass -File "$escaped"',
    };
  }

  CliInstallerCommand installerCommandForScriptFile(String scriptPath) {
    return switch (dialect) {
      HostScriptDialect.bash => CliInstallerCommand('bash', [scriptPath]),
      HostScriptDialect.powershell => CliInstallerCommand('powershell', [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        scriptPath,
      ]),
    };
  }

  CliInstallerCommand installerCommandForInline(String scriptBody) {
    return switch (dialect) {
      HostScriptDialect.bash => CliInstallerCommand.unixShellScript(scriptBody),
      HostScriptDialect.powershell => CliInstallerCommand('powershell', [
        '-NoProfile',
        '-Command',
        scriptBody,
      ]),
    };
  }
}
