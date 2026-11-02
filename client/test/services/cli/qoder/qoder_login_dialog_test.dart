import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/qoder/provider/qoder_login_dialog.dart';

void main() {
  group('qoderLoginEnvironment', () {
    test('isolates HOME and QODER_CONFIG_DIR, keeping the base env', () {
      final env = qoderLoginEnvironment(
        home: '/data/cli-login/qoder/work/home',
        configDir: '/data/cli-login/qoder/work/config',
        base: const {'PATH': '/usr/bin', 'HOME': '/home/user'},
      );
      expect(env['PATH'], '/usr/bin');
      expect(env['HOME'], '/data/cli-login/qoder/work/home');
      expect(env['QODER_CONFIG_DIR'], '/data/cli-login/qoder/work/config');
      expect(env['TERM'], 'xterm-256color');
      expect(env['COLORTERM'], 'truecolor');
      expect(env.containsKey('USERPROFILE'), isFalse);
    });

    test('also isolates USERPROFILE on Windows', () {
      final env = qoderLoginEnvironment(
        home: 'C:/data/cli-login/qoder/work/home',
        configDir: 'C:/data/cli-login/qoder/work/config',
        base: const {'USERPROFILE': r'C:\Users\user'},
        isWindows: true,
      );
      expect(env['USERPROFILE'], 'C:/data/cli-login/qoder/work/home');
    });

    test('never points at the global ~/.qoder', () {
      final env = qoderLoginEnvironment(
        home: '/data/cli-login/qoder/work/home',
        configDir: '/data/cli-login/qoder/work/config',
        base: const {'HOME': '/home/user'},
      );
      expect(env.values.where((value) => value.contains('.qoder')), isEmpty);
    });
  });
}
