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

    test('forStandaloneConfigDir sets CURSOR_CONFIG_DIR', () {
      const configDir = '/fake/config';

      final env = CursorLaunchEnvironment.forStandaloneConfigDir(configDir);

      expect(env['CURSOR_CONFIG_DIR'], configDir);
    });
  });
}
