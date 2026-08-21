import 'dart:io';

import 'package:path/path.dart' as p;

/// Path helpers for an isolated fake `$HOME/.cursor/` layout.
final class CursorHomeLayout {
  CursorHomeLayout({p.Context? pathContext})
    : _pathContext = pathContext ?? p.context;

  final p.Context _pathContext;

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

  String cursorDir(String homeRoot) =>
      _pathContext.join(homeRoot, cursorDirName);

  String configCursorDir(String homeRoot) =>
      _pathContext.join(homeRoot, configDirName, configCursorDirName);

  /// OAuth token file for [homeRoot].
  ///
  /// `cursor-agent` with `AGENT_CLI_CREDENTIAL_STORE=file` writes here:
  /// - macOS: `$HOME/.cursor/auth.json`
  /// - Linux / Windows: `$HOME/.config/cursor/auth.json`
  String authJson(String homeRoot) => Platform.isMacOS
      ? _pathContext.join(cursorDir(homeRoot), authFileName)
      : _pathContext.join(configCursorDir(homeRoot), authFileName);

  /// Probe/import order for [authJson] plus legacy paths.
  List<String> authJsonCandidates(String homeRoot) {
    final primary = authJson(homeRoot);
    if (!Platform.isMacOS) return [primary];
    final legacy = _pathContext.join(configCursorDir(homeRoot), authFileName);
    if (legacy == primary) return [primary];
    return [primary, legacy];
  }

  /// Live OAuth tokens on the user's machine, in probe order.
  ///
  /// Cursor IDE on Windows stores `auth.json` under `%APPDATA%\Cursor\`.
  /// `cursor-agent` file store: macOS `$HOME/.cursor/auth.json`; Linux
  /// `$HOME/.config/cursor/auth.json`. macOS IDE uses
  /// `~/Library/Application Support/Cursor/`.
  List<String> globalAuthJsonCandidates(
    String homeDirectory, {
    Map<String, String> platformEnv = const {},
  }) {
    final home = homeDirectory.trim();
    final candidates = <String>[];

    final appData =
        platformEnv['APPDATA']?.trim() ??
        (Platform.isWindows ? Platform.environment['APPDATA']?.trim() : null) ??
        '';
    if (appData.isNotEmpty) {
      candidates.add(_pathContext.join(appData, 'Cursor', authFileName));
    }

    if (Platform.isMacOS && home.isNotEmpty) {
      candidates.add(
        _pathContext.join(
          home,
          'Library',
          'Application Support',
          'Cursor',
          authFileName,
        ),
      );
    }

    if (home.isNotEmpty) {
      for (final candidate in authJsonCandidates(home)) {
        candidates.add(candidate);
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
