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
  static const configDirName = '.config';
  static const configCursorDirName = 'cursor';
  static const authFileName = 'auth.json';

  String cursorDir(String homeRoot) =>
      _pathContext.join(homeRoot, cursorDirName);

  String configCursorDir(String homeRoot) =>
      _pathContext.join(homeRoot, configDirName, configCursorDirName);

  String authJson(String homeRoot) =>
      _pathContext.join(configCursorDir(homeRoot), authFileName);

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
}
