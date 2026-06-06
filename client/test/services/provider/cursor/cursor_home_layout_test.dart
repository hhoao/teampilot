import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/provider/cursor/cursor_home_layout.dart';

void main() {
  group('CursorHomeLayout', () {
    const layout = CursorHomeLayout();
    const homeRoot = '/fake/home';

    test('cursorDir joins homeRoot with .cursor', () {
      expect(
        layout.cursorDir(homeRoot),
        p.join(homeRoot, CursorHomeLayout.cursorDirName),
      );
    });

    test('configCursorDir joins homeRoot with .config/cursor', () {
      expect(
        layout.configCursorDir(homeRoot),
        p.join(
          homeRoot,
          CursorHomeLayout.configDirName,
          CursorHomeLayout.configCursorDirName,
        ),
      );
    });

    test('authJson joins .config/cursor/auth.json under homeRoot', () {
      expect(
        layout.authJson(homeRoot),
        p.join(
          layout.configCursorDir(homeRoot),
          CursorHomeLayout.authFileName,
        ),
      );
    });

    test('roleRule joins rules/role.mdc under cursor dir', () {
      expect(
        layout.roleRule(homeRoot),
        p.join(
          layout.cursorDir(homeRoot),
          CursorHomeLayout.rulesDirName,
          CursorHomeLayout.roleRuleFileName,
        ),
      );
    });

    test('hooksConfig joins hooks.json under cursor dir', () {
      expect(
        layout.hooksConfig(homeRoot),
        p.join(
          layout.cursorDir(homeRoot),
          CursorHomeLayout.hooksFileName,
        ),
      );
    });

    test('idleScript joins hooks/idle.sh under cursor dir', () {
      expect(
        layout.idleScript(homeRoot),
        p.join(
          layout.cursorDir(homeRoot),
          CursorHomeLayout.hooksDirName,
          CursorHomeLayout.idleScriptFileName,
        ),
      );
    });

    test('mcpConfig joins mcp.json under cursor dir', () {
      expect(
        layout.mcpConfig(homeRoot),
        p.join(
          layout.cursorDir(homeRoot),
          CursorHomeLayout.mcpFileName,
        ),
      );
    });

    test('cliConfig joins cli-config.json under cursor dir', () {
      expect(
        layout.cliConfig(homeRoot),
        p.join(
          layout.cursorDir(homeRoot),
          CursorHomeLayout.cliConfigFileName,
        ),
      );
    });
  });
}
