import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:teampilot/services/cli/cursor/provider/cursor_launch_environment.dart';

void main() {
  group('CursorLaunchEnvironment', () {
    test(
      'forMixed sets HOME and USERPROFILE to same path when useWslPaths false',
      () {
        const homeRoot = '/fake/home';

        final env = CursorLaunchEnvironment.forMixed(
          homeRoot: homeRoot,
          useWslPaths: false,
        );

        expect(env['HOME'], homeRoot);
        expect(env['USERPROFILE'], homeRoot);
        expect(
          env[CursorLaunchEnvironment.credentialStoreEnvKey],
          CursorLaunchEnvironment.credentialStoreFile,
        );
      },
    );

    test('posix home pins XDG_CONFIG_HOME inside the isolated home', () {
      final env = CursorLaunchEnvironment.forMixed(
        homeRoot: '/fake/home',
        useWslPaths: false,
      );
      expect(env['XDG_CONFIG_HOME'], '/fake/home/.config');
      expect(env.containsKey('APPDATA'), isFalse);
    });

    test('windows home pins APPDATA inside the isolated home', () {
      final env = CursorLaunchEnvironment.forMixed(
        homeRoot: r'C:\tp\providers\cursor\work\home',
        useWslPaths: false,
      );
      // HOME is forward-slashed for the CLI, but APPDATA keeps Windows style.
      expect(env['HOME'], 'C:/tp/providers/cursor/work/home');
      expect(env['USERPROFILE'], 'C:/tp/providers/cursor/work/home');
      expect(
        env['APPDATA'],
        p.windows.join(
          r'C:\tp\providers\cursor\work\home',
          'AppData',
          'Roaming',
        ),
      );
      expect(env.containsKey('XDG_CONFIG_HOME'), isFalse);
    });

    test('WSL home pins XDG_CONFIG_HOME with the WSL path', () {
      final env = CursorLaunchEnvironment.forMixed(
        homeRoot: r'C:\tp\providers\cursor\work\home',
        useWslPaths: true,
      );
      expect(env['XDG_CONFIG_HOME'], '/mnt/c/tp/providers/cursor/work/home/.config');
      expect(env.containsKey('APPDATA'), isFalse);
    });

    test(
      'forStandalone HOME-isolates and sets CURSOR_CONFIG_DIR to .cursor',
      () {
        const homeRoot = '/fake/home';
        const cursorConfigDir = '/fake/home/.cursor';

        final env = CursorLaunchEnvironment.forStandalone(
          homeRoot: homeRoot,
          cursorConfigDir: cursorConfigDir,
        );

        expect(env['HOME'], homeRoot);
        expect(env['USERPROFILE'], homeRoot);
        expect(env['CURSOR_CONFIG_DIR'], cursorConfigDir);
        expect(env['XDG_CONFIG_HOME'], '/fake/home/.config');
        expect(
          env[CursorLaunchEnvironment.credentialStoreEnvKey],
          CursorLaunchEnvironment.credentialStoreFile,
        );
      },
    );
  });
}
