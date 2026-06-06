import '../../session/launch_command_builder.dart';

abstract final class CursorLaunchEnvironment {
  static Map<String, String> forMixed({
    required String homeRoot,
    required bool useWslPaths,
  }) {
    final home = useWslPaths
        ? LaunchCommandBuilder.normalizePathForCli(homeRoot, useWslPaths: true)
        : homeRoot;
    return {'HOME': home, 'USERPROFILE': home};
  }

  static Map<String, String> forStandaloneConfigDir(String configDir) =>
      {'CURSOR_CONFIG_DIR': configDir};
}
