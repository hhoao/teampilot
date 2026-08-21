import '../../../session/launch_command_builder.dart';

abstract final class CursorLaunchEnvironment {
  /// Force `cursor-agent` to read/write OAuth tokens as `auth.json` under the
  /// isolated fake `$HOME` instead of the macOS login keychain (`cursor-user`
  /// entries). TeamPilot isolates credentials per provider HOME.
  static const credentialStoreEnvKey = 'AGENT_CLI_CREDENTIAL_STORE';
  static const credentialStoreFile = 'file';

  static Map<String, String> forMixed({
    required String homeRoot,
    required bool useWslPaths,
  }) {
    var home = useWslPaths
        ? LaunchCommandBuilder.normalizePathForCli(homeRoot, useWslPaths: true)
        : homeRoot;
    if (!useWslPaths && home.contains(r'\')) {
      home = home.replaceAll(r'\', '/');
    }
    return _isolatedHomeEnv(home);
  }

  /// Standalone personal launch: isolate under a fake `$HOME` (so cursor reads
  /// the session's `~/.cursor` plugins/MCP/skills) AND point `CURSOR_CONFIG_DIR`
  /// at that same `.cursor` dir (so `cli-config.json`/`chats` — and resume —
  /// stay isolated too).
  static Map<String, String> forStandalone({
    required String homeRoot,
    required String cursorConfigDir,
  }) => _isolatedHomeEnv(
    homeRoot,
    extra: {'CURSOR_CONFIG_DIR': cursorConfigDir},
  );

  static Map<String, String> _isolatedHomeEnv(
    String home, {
    Map<String, String> extra = const {},
  }) => {
    'HOME': home,
    'USERPROFILE': home,
    credentialStoreEnvKey: credentialStoreFile,
    ...extra,
  };
}
