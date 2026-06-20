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

  /// Standalone personal launch: isolate under a fake `$HOME` (so cursor reads
  /// the session's `~/.cursor` plugins/MCP/skills) AND point `CURSOR_CONFIG_DIR`
  /// at that same `.cursor` dir (so `cli-config.json`/`chats` — and resume —
  /// stay isolated too).
  static Map<String, String> forStandalone({
    required String homeRoot,
    required String cursorConfigDir,
  }) => {
    'HOME': homeRoot,
    'USERPROFILE': homeRoot,
    'CURSOR_CONFIG_DIR': cursorConfigDir,
  };
}
