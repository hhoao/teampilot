import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/provider/cursor/cursor_home_layout.dart';

void main() {
  group('CursorHomeLayout', () {
    final layout = CursorHomeLayout();
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

    test('globalAuthJsonCandidates prefers APPDATA Cursor on Windows', () {
      final candidates = CursorHomeLayout().globalAuthJsonCandidates(
        r'C:\Users\haung',
        platformEnv: const {'APPDATA': r'C:\Users\haung\AppData\Roaming'},
      );
      expect(
        candidates.first,
        r'C:\Users\haung\AppData\Roaming\Cursor\auth.json',
      );
      expect(candidates.last, r'C:\Users\haung\.config\cursor\auth.json');
    });

    test('globalAuthJsonCandidates always includes xdg auth path', () {
      final candidates = CursorHomeLayout().globalAuthJsonCandidates(homeRoot);
      expect(candidates, contains(layout.authJson(homeRoot)));
    });
  });
}
