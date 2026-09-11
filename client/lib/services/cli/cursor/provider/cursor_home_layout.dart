import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// OS flavor that decides where cursor-agent anchors its credential files.
///
/// Mirrors cursor-agent's own `getAuthFilePath`:
/// - [windows]: `%APPDATA%\Cursor\auth.json` — `APPDATA` wins over any
///   HOME-derived fallback.
/// - [macos]: `$HOME/.cursor/auth.json`.
/// - [linux]: `${XDG_CONFIG_HOME:-$HOME/.config}/cursor/auth.json`.
///
/// Re-verify against a new cursor-agent release by grepping its bundle for
/// `getAuthFilePath` before changing any path below.
enum CursorHomePlatform {
  windows,
  macos,
  linux;

  /// OS TeamPilot itself runs on.
  static CursorHomePlatform get current => switch (Platform.operatingSystem) {
    'windows' => CursorHomePlatform.windows,
    'macos' => CursorHomePlatform.macos,
    _ => CursorHomePlatform.linux,
  };

  /// Derives the platform governing [pathContext]: Windows-style paths mean
  /// native Windows; POSIX paths on a macOS host mean a local macOS home;
  /// every other POSIX context (Linux desktop, WSL, SSH work plane) is Linux.
  static CursorHomePlatform resolve(p.Context pathContext) {
    if (pathContext.style == p.Style.windows) return CursorHomePlatform.windows;
    return CursorHomePlatform.current == CursorHomePlatform.macos
        ? CursorHomePlatform.macos
        : CursorHomePlatform.linux;
  }
}

/// Path helpers for an isolated fake `$HOME/.cursor/` layout.
///
/// The layout is a pure function of ([CursorHomePlatform], path style) — never
/// of the host OS directly — so tests can exercise every platform from any
/// machine and remote (SSH/WSL) planes resolve correctly.
final class CursorHomeLayout {
  CursorHomeLayout({p.Context? pathContext, CursorHomePlatform? platform})
    : _pathContext = pathContext ?? p.context,
      _platform = platform ?? CursorHomePlatform.resolve(pathContext ?? p.context);

  final p.Context _pathContext;
  final CursorHomePlatform _platform;

  static const cursorDirName = '.cursor';
  static const rulesDirName = 'rules';
  static const roleRuleFileName = 'role.mdc';
  static const hooksDirName = 'hooks';
  static const hooksFileName = 'hooks.json';
  static const idleScriptFileName = 'idle.sh';
  static const mcpFileName = 'mcp.json';
  static const cliConfigFileName = 'cli-config.json';
  static const agentCliStateFileName = 'agent-cli-state.json';
  static const statsigCacheFileName = 'statsig-cache.json';
  static const pluginsDirName = 'plugins';
  static const pluginsCacheSegment = 'cache';
  static const configDirName = '.config';
  static const configCursorDirName = 'cursor';
  static const authFileName = 'auth.json';

  /// When set, the `Platform.environment` fallbacks in
  /// [globalAuthJsonCandidates] read from here instead of the real host
  /// environment. Tests pin this to `const {}` so "XDG_CONFIG_HOME/APPDATA
  /// unset" holds on every machine — CI runners export XDG_CONFIG_HOME, which
  /// would otherwise change the candidates the suite observes.
  @visibleForTesting
  static Map<String, String>? debugPlatformEnvironmentOverride;

  static String? _hostEnv(String key) =>
      (debugPlatformEnvironmentOverride ?? Platform.environment)[key];

  /// Windows: `%APPDATA%` root segment inside an isolated home.
  static const windowsAppDataDirName = 'AppData';
  static const windowsRoamingDirName = 'Roaming';

  /// Windows: cursor-agent title-cases its app dir (`Cursor`, not `cursor`).
  static const windowsCursorDirName = 'Cursor';

  /// macOS: Cursor IDE stores `auth.json` here.
  static const macOsIdeSupportSegments = ['Library', 'Application Support', 'Cursor'];

  String cursorDir(String homeRoot) =>
      _pathContext.join(homeRoot, cursorDirName);

  String configCursorDir(String homeRoot) =>
      _pathContext.join(homeRoot, configDirName, configCursorDirName);

  /// Directory holding `auth.json` for [homeRoot] — the credential anchor for
  /// the layout's platform (see [CursorHomePlatform]).
  String authDir(String homeRoot) => switch (_platform) {
    CursorHomePlatform.windows => _pathContext.join(
      homeRoot,
      windowsAppDataDirName,
      windowsRoamingDirName,
      windowsCursorDirName,
    ),
    CursorHomePlatform.macos => cursorDir(homeRoot),
    CursorHomePlatform.linux => configCursorDir(homeRoot),
  };

  /// OAuth token file for [homeRoot] (cursor-agent `getAuthFilePath`).
  String authJson(String homeRoot) =>
      _pathContext.join(authDir(homeRoot), authFileName);

  /// Top-level `$HOME` entries that must stay isolated in a member home —
  /// never passthrough-linked from the real home.
  ///
  /// `.cursor` always; `AppData` on Windows because a linked `AppData` would
  /// route the pinned `APPDATA` env (and thus cursor credentials) back to the
  /// real user's Roaming profile.
  List<String> isolatedTopLevelEntries() => switch (_platform) {
    CursorHomePlatform.windows => [cursorDirName, windowsAppDataDirName],
    _ => [cursorDirName],
  };

  /// Live OAuth tokens on the user's machine, in probe order.
  ///
  /// - Windows: Cursor IDE / cursor-agent under `%APPDATA%\Cursor\`, plus the
  ///   HOME-derived fallback cursor-agent uses when `APPDATA` is unset.
  /// - macOS: Cursor IDE under `~/Library/Application Support/Cursor/`, then
  ///   the cursor-agent file store `~/.cursor/auth.json`.
  /// - Linux: `${XDG_CONFIG_HOME:-~/.config}/cursor/auth.json`.
  List<String> globalAuthJsonCandidates(
    String homeDirectory, {
    Map<String, String> platformEnv = const {},
  }) {
    final home = homeDirectory.trim();
    final candidates = <String>[];

    switch (_platform) {
      case CursorHomePlatform.windows:
        final appData =
            platformEnv['APPDATA']?.trim() ??
            (Platform.isWindows ? _hostEnv('APPDATA')?.trim() : null) ??
            '';
        if (appData.isNotEmpty) {
          candidates.add(_pathContext.join(appData, windowsCursorDirName, authFileName));
        }
        if (home.isNotEmpty) {
          candidates.add(authJson(home));
        }
      case CursorHomePlatform.macos:
        if (home.isNotEmpty) {
          candidates.add(
            _pathContext.joinAll([home, ...macOsIdeSupportSegments, authFileName]),
          );
          candidates.add(_pathContext.join(cursorDir(home), authFileName));
        }
      case CursorHomePlatform.linux:
        if (home.isNotEmpty) {
          final xdg =
              platformEnv['XDG_CONFIG_HOME']?.trim() ??
              (Platform.isLinux ? _hostEnv('XDG_CONFIG_HOME')?.trim() : null) ??
              '';
          final configRoot = xdg.isNotEmpty
                  ? xdg
                  : _pathContext.join(home, configDirName);
          candidates.add(
            _pathContext.join(configRoot, configCursorDirName, authFileName),
          );
        }
    }
    return candidates;
  }

  String roleRule(String homeRoot) =>
      _pathContext.join(cursorDir(homeRoot), rulesDirName, roleRuleFileName);

  String hooksConfig(String homeRoot) =>
      _pathContext.join(cursorDir(homeRoot), hooksFileName);

  String hooksDir(String homeRoot) =>
      _pathContext.join(cursorDir(homeRoot), hooksDirName);

  String idleScript(String homeRoot) =>
      _pathContext.join(cursorDir(homeRoot), hooksDirName, idleScriptFileName);

  /// Agent-status forwarding script path under `~/.cursor/hooks/`.
  String agentStatusScript(String homeRoot, String fileName) =>
      _pathContext.join(cursorDir(homeRoot), hooksDirName, fileName);

  String mcpConfig(String homeRoot) =>
      _pathContext.join(cursorDir(homeRoot), mcpFileName);

  String cliConfig(String homeRoot) =>
      _pathContext.join(cursorDir(homeRoot), cliConfigFileName);

  String agentCliState(String homeRoot) =>
      _pathContext.join(cursorDir(homeRoot), agentCliStateFileName);

  String statsigCache(String homeRoot) =>
      _pathContext.join(cursorDir(homeRoot), statsigCacheFileName);

  /// cursor-agent marketplace extract dir (`~/.cursor/plugins/cache`).
  String pluginsCache(String homeRoot) => _pathContext.join(
    cursorDir(homeRoot),
    pluginsDirName,
    pluginsCacheSegment,
  );
}
