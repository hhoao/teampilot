import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:teampilot/services/cli/cursor/provider/cursor_home_layout.dart';

void main() {
  group('CursorHomeLayout', () {
    final posix = p.Context(style: p.Style.posix);
    final windows = p.Context(style: p.Style.windows);
    const homeRoot = '/fake/home';

    test('cursorDir joins homeRoot with .cursor', () {
      final layout = CursorHomeLayout(pathContext: posix);
      expect(
        layout.cursorDir(homeRoot),
        posix.join(homeRoot, CursorHomeLayout.cursorDirName),
      );
    });

    test('configCursorDir joins homeRoot with .config/cursor', () {
      final layout = CursorHomeLayout(pathContext: posix);
      expect(
        layout.configCursorDir(homeRoot),
        posix.join(
          homeRoot,
          CursorHomeLayout.configDirName,
          CursorHomeLayout.configCursorDirName,
        ),
      );
    });

    test('authJson mirrors cursor-agent getAuthFilePath per platform', () {
      // Windows: %APPDATA%\Cursor\auth.json.
      expect(
        CursorHomeLayout(
          pathContext: windows,
          platform: CursorHomePlatform.windows,
        ).authJson(homeRoot),
        windows.join(
          homeRoot,
          'AppData',
          'Roaming',
          'Cursor',
          CursorHomeLayout.authFileName,
        ),
      );
      // macOS: $HOME/.cursor/auth.json.
      expect(
        CursorHomeLayout(
          pathContext: posix,
          platform: CursorHomePlatform.macos,
        ).authJson(homeRoot),
        posix.join(
          homeRoot,
          CursorHomeLayout.cursorDirName,
          CursorHomeLayout.authFileName,
        ),
      );
      // Linux: $HOME/.config/cursor/auth.json.
      expect(
        CursorHomeLayout(
          pathContext: posix,
          platform: CursorHomePlatform.linux,
        ).authJson(homeRoot),
        posix.join(
          homeRoot,
          CursorHomeLayout.configDirName,
          CursorHomeLayout.configCursorDirName,
          CursorHomeLayout.authFileName,
        ),
      );
    });

    test('authDir is the parent of authJson on every platform', () {
      for (final platform in CursorHomePlatform.values) {
        final layout = CursorHomeLayout(
          pathContext: posix,
          platform: platform,
        );
        expect(posix.dirname(layout.authJson(homeRoot)), layout.authDir(homeRoot));
      }
    });

    test('isolatedTopLevelEntries excludes AppData only on Windows', () {
      expect(
        CursorHomeLayout(
          pathContext: windows,
          platform: CursorHomePlatform.windows,
        ).isolatedTopLevelEntries(),
        [CursorHomeLayout.cursorDirName, 'AppData'],
      );
      expect(
        CursorHomeLayout(
          pathContext: posix,
          platform: CursorHomePlatform.linux,
        ).isolatedTopLevelEntries(),
        [CursorHomeLayout.cursorDirName],
      );
      expect(
        CursorHomeLayout(
          pathContext: posix,
          platform: CursorHomePlatform.macos,
        ).isolatedTopLevelEntries(),
        [CursorHomeLayout.cursorDirName],
      );
    });

    test('roleRule joins rules/role.mdc under cursor dir', () {
      final layout = CursorHomeLayout(pathContext: posix);
      expect(
        layout.roleRule(homeRoot),
        posix.join(
          homeRoot,
          CursorHomeLayout.cursorDirName,
          CursorHomeLayout.rulesDirName,
          CursorHomeLayout.roleRuleFileName,
        ),
      );
    });

    test('hooksConfig joins hooks.json under cursor dir', () {
      final layout = CursorHomeLayout(pathContext: posix);
      expect(
        layout.hooksConfig(homeRoot),
        posix.join(
          homeRoot,
          CursorHomeLayout.cursorDirName,
          CursorHomeLayout.hooksFileName,
        ),
      );
    });

    test('idleScript joins hooks/idle.sh under cursor dir', () {
      final layout = CursorHomeLayout(pathContext: posix);
      expect(
        layout.idleScript(homeRoot),
        posix.join(
          homeRoot,
          CursorHomeLayout.cursorDirName,
          CursorHomeLayout.hooksDirName,
          CursorHomeLayout.idleScriptFileName,
        ),
      );
    });

    test('mcpConfig joins mcp.json under cursor dir', () {
      final layout = CursorHomeLayout(pathContext: posix);
      expect(
        layout.mcpConfig(homeRoot),
        posix.join(
          homeRoot,
          CursorHomeLayout.cursorDirName,
          CursorHomeLayout.mcpFileName,
        ),
      );
    });

    test('cliConfig joins cli-config.json under cursor dir', () {
      final layout = CursorHomeLayout(pathContext: posix);
      expect(
        layout.cliConfig(homeRoot),
        posix.join(
          homeRoot,
          CursorHomeLayout.cursorDirName,
          CursorHomeLayout.cliConfigFileName,
        ),
      );
    });

    test('pluginsCache joins plugins/cache under cursor dir', () {
      final layout = CursorHomeLayout(pathContext: posix);
      expect(
        layout.pluginsCache(homeRoot),
        posix.join(
          homeRoot,
          CursorHomeLayout.cursorDirName,
          CursorHomeLayout.pluginsDirName,
          CursorHomeLayout.pluginsCacheSegment,
        ),
      );
    });

    test('agentCliState joins agent-cli-state.json under cursor dir', () {
      final layout = CursorHomeLayout(pathContext: posix);
      expect(
        layout.agentCliState(homeRoot),
        posix.join(
          homeRoot,
          CursorHomeLayout.cursorDirName,
          CursorHomeLayout.agentCliStateFileName,
        ),
      );
    });

    group('globalAuthJsonCandidates', () {
      test('windows prefers APPDATA Cursor then home-derived Roaming', () {
        final layout = CursorHomeLayout(
          pathContext: windows,
          platform: CursorHomePlatform.windows,
        );
        final candidates = layout.globalAuthJsonCandidates(
          r'C:\Users\haung',
          platformEnv: const {'APPDATA': r'C:\Users\haung\AppData\Roaming'},
        );
        expect(candidates, hasLength(2));
        expect(
          candidates.first,
          windows.join(
            r'C:\Users\haung\AppData\Roaming',
            'Cursor',
            CursorHomeLayout.authFileName,
          ),
        );
        expect(
          candidates.last,
          windows.join(
            r'C:\Users\haung',
            'AppData',
            'Roaming',
            'Cursor',
            CursorHomeLayout.authFileName,
          ),
        );
      });

      test('macos lists IDE support dir then file store', () {
        final layout = CursorHomeLayout(
          pathContext: posix,
          platform: CursorHomePlatform.macos,
        );
        final candidates = layout.globalAuthJsonCandidates(homeRoot);
        expect(candidates, hasLength(2));
        expect(
          candidates.first,
          posix.join(
            homeRoot,
            'Library',
            'Application Support',
            'Cursor',
            CursorHomeLayout.authFileName,
          ),
        );
        expect(candidates.last, layout.authJson(homeRoot));
      });

      test('linux honors XDG_CONFIG_HOME when set', () {
        final layout = CursorHomeLayout(
          pathContext: posix,
          platform: CursorHomePlatform.linux,
        );
        expect(
          layout.globalAuthJsonCandidates(
            homeRoot,
            platformEnv: const {'XDG_CONFIG_HOME': '/custom/xdg'},
          ),
          [
            posix.join(
              '/custom/xdg',
              CursorHomeLayout.configCursorDirName,
              CursorHomeLayout.authFileName,
            ),
          ],
        );
      });

      test('linux defaults to \$HOME/.config/cursor', () {
        final layout = CursorHomeLayout(
          pathContext: posix,
          platform: CursorHomePlatform.linux,
        );
        expect(layout.globalAuthJsonCandidates(homeRoot), [
          layout.authJson(homeRoot),
        ]);
      });
    });

    test('CursorHomePlatform.resolve maps windows path style to windows', () {
      expect(
        CursorHomePlatform.resolve(windows),
        CursorHomePlatform.windows,
      );
    });
  });
}
