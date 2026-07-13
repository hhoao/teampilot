import 'package:flutter/foundation.dart';

import '../../models/run/launch_configuration.dart';
import 'shell_script_launch_schema.dart';

/// Typed view of a `shellScript` [LaunchConfiguration] (known fields + extras).
@immutable
class ShellScriptConfiguration {
  const ShellScriptConfiguration({
    required this.execute,
    this.scriptPath,
    this.scriptText,
    this.scriptOptions = '',
    required this.interpreterPath,
    this.interpreterOptions = '',
    this.cwd,
    this.env = const {},
    this.executeInTerminal = true,
    this.allowMultipleInstances = false,
    this.activateToolWindow = true,
    this.focusToolWindow = false,
  });

  /// `scriptFile` or `scriptText`.
  final String execute;
  final String? scriptPath;
  final String? scriptText;
  final String scriptOptions;
  final String interpreterPath;
  final String interpreterOptions;
  final String? cwd;
  final Map<String, String> env;
  final bool executeInTerminal;
  final bool allowMultipleInstances;
  final bool activateToolWindow;
  final bool focusToolWindow;

  /// Merges [LaunchConfiguration.toJson] known fields and extras into a typed
  /// shell-script view (shell fields often live only in [LaunchConfiguration.extras]).
  factory ShellScriptConfiguration.fromLaunchConfiguration(
    LaunchConfiguration configuration,
  ) {
    final map = configuration.toJson();
    final execute = _string(map['execute']) ?? 'scriptFile';
    final interpreterPath = _string(map['interpreterPath'])?.trim();
    final cwd = _string(map['cwd'])?.trim();
    return ShellScriptConfiguration(
      execute: execute,
      scriptPath: _string(map['scriptPath']),
      scriptText: _string(map['scriptText']),
      scriptOptions: _string(map['scriptOptions']) ?? '',
      interpreterPath: (interpreterPath != null && interpreterPath.isNotEmpty)
          ? interpreterPath
          : ShellScriptLaunchSchema.defaultInterpreterPath(),
      interpreterOptions: _string(map['interpreterOptions']) ?? '',
      cwd: (cwd != null && cwd.isNotEmpty) ? cwd : r'${workspaceFolder}',
      env: _stringMap(map['env']),
      executeInTerminal: _bool(map['executeInTerminal']) ?? true,
      allowMultipleInstances: _bool(map['allowMultipleInstances']) ?? false,
      activateToolWindow: _bool(map['activateToolWindow']) ?? true,
      focusToolWindow: _bool(map['focusToolWindow']) ?? false,
    );
  }

  bool get isScriptFile => execute == 'scriptFile';
  bool get isScriptText => execute == 'scriptText';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ShellScriptConfiguration &&
          runtimeType == other.runtimeType &&
          execute == other.execute &&
          scriptPath == other.scriptPath &&
          scriptText == other.scriptText &&
          scriptOptions == other.scriptOptions &&
          interpreterPath == other.interpreterPath &&
          interpreterOptions == other.interpreterOptions &&
          cwd == other.cwd &&
          mapEquals(env, other.env) &&
          executeInTerminal == other.executeInTerminal &&
          allowMultipleInstances == other.allowMultipleInstances &&
          activateToolWindow == other.activateToolWindow &&
          focusToolWindow == other.focusToolWindow;

  @override
  int get hashCode => Object.hash(
    execute,
    scriptPath,
    scriptText,
    scriptOptions,
    interpreterPath,
    interpreterOptions,
    cwd,
    Object.hashAll(env.entries),
    executeInTerminal,
    allowMultipleInstances,
    activateToolWindow,
    focusToolWindow,
  );
}

String? _string(Object? raw) => raw is String ? raw : null;

bool? _bool(Object? raw) => raw is bool ? raw : null;

Map<String, String> _stringMap(Object? raw) {
  if (raw is! Map) return const {};
  return {
    for (final entry in raw.entries)
      if (entry.key != null) entry.key.toString(): entry.value?.toString() ?? '',
  };
}
