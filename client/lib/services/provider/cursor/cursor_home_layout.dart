import 'package:path/path.dart' as p;

/// Path helpers for an isolated fake `$HOME/.cursor/` layout.
final class CursorHomeLayout {
  const CursorHomeLayout();

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

  String cursorDir(String homeRoot) => p.join(homeRoot, cursorDirName);

  String configCursorDir(String homeRoot) =>
      p.join(homeRoot, configDirName, configCursorDirName);

  String authJson(String homeRoot) =>
      p.join(configCursorDir(homeRoot), authFileName);

  String roleRule(String homeRoot) =>
      p.join(cursorDir(homeRoot), rulesDirName, roleRuleFileName);

  String hooksConfig(String homeRoot) =>
      p.join(cursorDir(homeRoot), hooksFileName);

  String idleScript(String homeRoot) =>
      p.join(cursorDir(homeRoot), hooksDirName, idleScriptFileName);

  String mcpConfig(String homeRoot) =>
      p.join(cursorDir(homeRoot), mcpFileName);

  String cliConfig(String homeRoot) =>
      p.join(cursorDir(homeRoot), cliConfigFileName);
}
