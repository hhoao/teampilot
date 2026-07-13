import '../../models/run/launch_configuration.dart';
import 'shell_script_launch_schema.dart';

/// Deterministic `type: process` → `shellScript` migration (on read / parse).
///
/// Wired through [LaunchConfiguration.fromJson] via [maybeMigrate] so every
/// parse path (store, document, ad-hoc) normalizes legacy process configs.
/// Writers emit whatever [LaunchConfiguration.toJson] produces; after migration
/// that no longer includes `command` / `args` / `shell` or `type: process`.
abstract final class ShellScriptMigrator {
  /// Returns [json] unchanged when not a process config; otherwise [migrate].
  static Map<String, Object?> maybeMigrate(Map<String, Object?> json) {
    if (json['type'] != ShellScriptLaunchSchema.processAlias) {
      return json;
    }
    return migrate(json);
  }

  /// Converts a process launch map to shellScript fields (spec branching rules).
  static Map<String, Object?> migrate(Map<String, Object?> raw) {
    if (raw['type'] != ShellScriptLaunchSchema.processAlias) {
      return Map<String, Object?>.from(raw);
    }

    final command = raw['command'] as String? ?? '';
    final args = _stringList(raw['args']);
    final shell = raw['shell'] == true;

    final tokens = <String>[
      if (command.isNotEmpty) command,
      ...args,
    ];

    final scriptText = shell
        ? tokens.join(' ')
        : tokens.map(posixShellQuote).join(' ');

    final out = Map<String, Object?>.from(raw);
    out['type'] = ShellScriptLaunchSchema.typeName;
    out['execute'] = 'scriptText';
    out['scriptText'] = scriptText;
    out['scriptOptions'] = '';
    out['interpreterPath'] = ShellScriptLaunchSchema.defaultInterpreterPath();
    out['interpreterOptions'] = '';
    out['executeInTerminal'] = false;
    out['allowMultipleInstances'] = false;
    out['activateToolWindow'] = true;
    out['focusToolWindow'] = false;
    out.remove('command');
    out.remove('args');
    out.remove('shell');
    return out;
  }

  /// Migrates an in-memory [LaunchConfiguration] when `type == process`.
  static LaunchConfiguration migrateConfiguration(
    LaunchConfiguration configuration,
  ) {
    if (configuration.type != ShellScriptLaunchSchema.processAlias) {
      return configuration;
    }
    return LaunchConfiguration.fromJson(migrate(configuration.toJson()));
  }

  /// POSIX single-quote wrap with `'\''` escape for embedded quotes.
  static String posixShellQuote(String value) =>
      "'${value.replaceAll("'", r"'\''")}'";

  static List<String> _stringList(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item != null) item.toString(),
    ];
  }
}
