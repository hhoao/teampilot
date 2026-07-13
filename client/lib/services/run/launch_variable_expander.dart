import 'package:teampilot/models/run/launch_configuration.dart';

/// Expands VS Code-style launch variables in configuration fields.
class LaunchVariableExpander {
  LaunchVariableExpander._();

  static final RegExp _envPattern = RegExp(r'\$\{env:([^}]+)\}');

  /// Shell-script string fields that commonly live in [LaunchConfiguration.extras].
  static const _shellScriptExtraKeys = {
    'scriptPath',
    'scriptText',
    'interpreterPath',
    'interpreterOptions',
    'scriptOptions',
  };

  static String expand(
    String input, {
    required String workspaceFolder,
    Map<String, String> env = const {},
  }) {
    var out = input.replaceAll(r'${workspaceFolder}', workspaceFolder);
    out = out.replaceAllMapped(_envPattern, (match) {
      final key = match.group(1)?.trim() ?? '';
      if (key.isEmpty) return match.group(0) ?? '';
      return env[key] ?? match.group(0)!;
    });
    return out;
  }

  static List<String> expandStringList(
    List<String> values, {
    required String workspaceFolder,
    Map<String, String> env = const {},
  }) {
    return [
      for (final value in values)
        expand(value, workspaceFolder: workspaceFolder, env: env),
    ];
  }

  static Map<String, String> expandEnvMap(
    Map<String, String> values, {
    required String workspaceFolder,
    Map<String, String> env = const {},
  }) {
    return {
      for (final entry in values.entries)
        entry.key: expand(
          entry.value,
          workspaceFolder: workspaceFolder,
          env: env,
        ),
    };
  }

  static LaunchConfiguration expandConfiguration(
    LaunchConfiguration configuration, {
    required String workspaceFolder,
    Map<String, String> env = const {},
  }) {
    final expandedEnv = expandEnvMap(
      configuration.env,
      workspaceFolder: workspaceFolder,
      env: env,
    );
    final mergedEnv = {...env, ...expandedEnv};

    return configuration.copyWith(
      cwd: configuration.cwd == null
          ? null
          : expand(
              configuration.cwd!,
              workspaceFolder: workspaceFolder,
              env: mergedEnv,
            ),
      env: expandedEnv,
      extras: _expandShellScriptExtras(
        configuration.extras,
        workspaceFolder: workspaceFolder,
        env: mergedEnv,
      ),
    );
  }

  static Map<String, Object?> _expandShellScriptExtras(
    Map<String, Object?> extras, {
    required String workspaceFolder,
    required Map<String, String> env,
  }) {
    if (extras.isEmpty) return extras;

    final out = Map<String, Object?>.from(extras);
    for (final key in _shellScriptExtraKeys) {
      final value = out[key];
      if (value is! String) continue;
      out[key] = expand(
        value,
        workspaceFolder: workspaceFolder,
        env: env,
      );
    }
    return out;
  }
}
