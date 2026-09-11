import 'package:path/path.dart' as p;

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

  /// Env that pins every credential anchor cursor-agent consults
  /// (`getAuthFilePath`) inside the isolated home:
  ///
  /// - Windows: `%APPDATA%\Cursor\auth.json` — `APPDATA` takes priority over
  ///   any HOME-derived fallback, so pin it to `<home>\AppData\Roaming`;
  ///   otherwise login/launch tokens silently land in the user's real Roaming
  ///   profile and provider isolation is a no-op.
  /// - POSIX: `${XDG_CONFIG_HOME:-$HOME/.config}/cursor/auth.json` — pin
  ///   `XDG_CONFIG_HOME` so a user-level XDG var cannot leak real credentials
  ///   into (or drain session tokens out of) the isolated home. Harmless on
  ///   macOS, where cursor-agent reads `$HOME/.cursor/auth.json` directly.
  ///
  /// The parent environment is still inherited by child processes; entries
  /// here override it.
  static Map<String, String> _isolatedHomeEnv(
    String home, {
    Map<String, String> extra = const {},
  }) {
    final windowsHome = isWindowsHomePath(home);
    return {
      'HOME': home,
      'USERPROFILE': home,
      credentialStoreEnvKey: credentialStoreFile,
      // Normalize so the pinned anchor is spelled exactly like the paths
      // TeamPilot probes (HOME above keeps forward slashes for the CLI).
      if (windowsHome)
        'APPDATA': p.windows.normalize(
          p.windows.joinAll([home, ...windowsAppDataPathSegments]),
        )
      else
        'XDG_CONFIG_HOME': p.posix.normalize(
          p.posix.joinAll([home, ...xdgConfigPathSegments]),
        ),
      ...extra,
    };
  }

  /// True when [home] is a native Windows home (drive letter or UNC).
  ///
  /// A leading `/` is POSIX — including WSL paths like `/mnt/c/...` — even
  /// though `p.windows.isAbsolute` also accepts root-relative Windows paths.
  static bool isWindowsHomePath(String home) =>
      !home.startsWith('/') && p.windows.isAbsolute(home);

  static const windowsAppDataPathSegments = ['AppData', 'Roaming'];
  static const xdgConfigPathSegments = ['.config'];
}
