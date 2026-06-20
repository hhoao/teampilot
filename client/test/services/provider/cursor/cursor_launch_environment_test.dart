import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/provider/cursor/cursor_launch_environment.dart';

void main() {
  group('CursorLaunchEnvironment', () {
    test('forMixed sets HOME and USERPROFILE to same path when useWslPaths false', () {
      const homeRoot = '/fake/home';

      final env = CursorLaunchEnvironment.forMixed(
        homeRoot: homeRoot,
        useWslPaths: false,
      );

      expect(env['HOME'], homeRoot);
      expect(env['USERPROFILE'], homeRoot);
    });

    test('forStandalone HOME-isolates and sets CURSOR_CONFIG_DIR to .cursor', () {
      const homeRoot = '/fake/home';
      const cursorConfigDir = '/fake/home/.cursor';

      final env = CursorLaunchEnvironment.forStandalone(
        homeRoot: homeRoot,
        cursorConfigDir: cursorConfigDir,
      );

      expect(env['HOME'], homeRoot);
      expect(env['USERPROFILE'], homeRoot);
      expect(env['CURSOR_CONFIG_DIR'], cursorConfigDir);
    });
  });
}
