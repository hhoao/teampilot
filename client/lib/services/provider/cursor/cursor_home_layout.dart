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
  static const configDirName = '.config';
  static const configCursorDirName = 'cursor';
  static const authFileName = 'auth.json';

  String cursorDir(String homeRoot) =>
      _pathContext.join(homeRoot, cursorDirName);

  String configCursorDir(String homeRoot) =>
      _pathContext.join(homeRoot, configDirName, configCursorDirName);

  String authJson(String homeRoot) =>
      _pathContext.join(configCursorDir(homeRoot), authFileName);

  /// Live OAuth tokens on the user's machine, in probe order.
  ///
  /// Cursor IDE on Windows stores `auth.json` under `%APPDATA%\Cursor\`.
  /// `cursor-agent login` writes to `$HOME/.config/cursor/auth.json` on all
  /// platforms. macOS IDE uses `~/Library/Application Support/Cursor/`.
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
      candidates.add(authJson(home));
    }
    return candidates;
  }

  String roleRule(String homeRoot) =>
      _pathContext.join(cursorDir(homeRoot), rulesDirName, roleRuleFileName);

  String hooksConfig(String homeRoot) =>
      _pathContext.join(cursorDir(homeRoot), hooksFileName);

  String idleScript(String homeRoot) =>
      _pathContext.join(cursorDir(homeRoot), hooksDirName, idleScriptFileName);

  String mcpConfig(String homeRoot) =>
      _pathContext.join(cursorDir(homeRoot), mcpFileName);

  String cliConfig(String homeRoot) =>
      _pathContext.join(cursorDir(homeRoot), cliConfigFileName);

  String agentCliState(String homeRoot) =>
      _pathContext.join(cursorDir(homeRoot), agentCliStateFileName);
}
