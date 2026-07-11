import 'package:teampilot/models/run/launch_configuration.dart';

/// Expands VS Code-style launch variables in configuration fields.
class LaunchVariableExpander {
  LaunchVariableExpander._();

  static final RegExp _envPattern = RegExp(r'\$\{env:([^}]+)\}');

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
      command: configuration.command == null
          ? null
          : expand(
              configuration.command!,
              workspaceFolder: workspaceFolder,
              env: mergedEnv,
            ),
      args: expandStringList(
        configuration.args,
        workspaceFolder: workspaceFolder,
        env: mergedEnv,
      ),
      cwd: configuration.cwd == null
          ? null
          : expand(
              configuration.cwd!,
              workspaceFolder: workspaceFolder,
              env: mergedEnv,
            ),
      env: expandedEnv,
    );
  }
}
