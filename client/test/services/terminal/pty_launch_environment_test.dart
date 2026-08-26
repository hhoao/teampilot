import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/host/host_shell_path_resolver.dart';
import 'package:teampilot/services/terminal/pty_launch_environment.dart';

void main() {
  test('buildPtyEnvironment injects TERM_PROGRAM and VTE_VERSION', () {
    final env = PtyLaunchEnvironment.buildPtyEnvironment(const {'FOO': 'bar'});
    expect(env['TERM_PROGRAM'], PtyLaunchEnvironment.termProgram);
    expect(env['VTE_VERSION'], PtyLaunchEnvironment.vteVersion);
    expect(env['FOO'], 'bar');
  });

  test('buildPtyEnvironment does not override explicit TERM_PROGRAM', () {
    final env = PtyLaunchEnvironment.buildPtyEnvironment(const {
      'TERM_PROGRAM': 'custom',
    });
    expect(env['TERM_PROGRAM'], 'custom');
    expect(env['VTE_VERSION'], PtyLaunchEnvironment.vteVersion);
  });

  test(
    'buildPtyEnvironment leaves COLORFGBG untouched when no theme is given',
    () {
      final env = PtyLaunchEnvironment.buildPtyEnvironment(const {});
      // No theme → we neither add nor rewrite it; it stays whatever was inherited.
      expect(env['COLORFGBG'], Platform.environment['COLORFGBG']);
    },
  );

  test(
    'buildPtyEnvironment maps a dark theme background to COLORFGBG 15;0',
    () {
      final env = PtyLaunchEnvironment.buildPtyEnvironment(
        const {},
        themeBackground: 0x0A0C10,
      );
      expect(env['COLORFGBG'], '15;0');
    },
  );

  test(
    'buildPtyEnvironment maps a light theme background to COLORFGBG 0;15',
    () {
      final env = PtyLaunchEnvironment.buildPtyEnvironment(
        const {},
        themeBackground: 0xF7F9FC,
      );
      expect(env['COLORFGBG'], '0;15');
    },
  );

  test(
    'applyColorScheme overrides an inherited COLORFGBG with the embedded bg',
    () {
      final env = <String, String>{'COLORFGBG': '0;15'}; // host says light
      PtyLaunchEnvironment.applyColorScheme(
        env,
        background: 0x0A0C10,
      ); // we are dark
      expect(env['COLORFGBG'], '15;0');
    },
  );

  test(
    'buildPtyEnvironment omits host Platform.environment for SSH remote launches',
    () {
      final env = PtyLaunchEnvironment.buildPtyEnvironment(const {
        'CLAUDE_CONFIG_DIR': '/tmp/claude',
      }, inheritHostEnvironment: false);
      expect(env['CLAUDE_CONFIG_DIR'], '/tmp/claude');
      expect(env['TERM_PROGRAM'], PtyLaunchEnvironment.termProgram);
      if (Platform.environment.containsKey('HOME')) {
        expect(env.containsKey('HOME'), isFalse);
      }
      if (Platform.environment.containsKey('PATH')) {
        expect(env.containsKey('PATH'), isFalse);
      }
      if (Platform.environment.containsKey('HTTP_PROXY')) {
        expect(env.containsKey('HTTP_PROXY'), isFalse);
      }
    },
  );

  group('applyLocalLoginShellPath', () {
    late Directory tempDir;
    late String candidateA;
    late String candidateB;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('tp_path_candidates');
      candidateA = '${tempDir.path}/a';
      candidateB = '${tempDir.path}/b';
      Directory(candidateA).createSync();
      Directory(candidateB).createSync();
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
      HostShellPathResolver.resetForTest();
    });

    test('resolved PATH fills between prepends and host-base leftovers', () {
      HostShellPathResolver.debugSetCachedPath('/home/.nvm/bin:/sparse/bin');
      final env = {'PATH': '/skill/bin:/sparse/bin'};
      PtyLaunchEnvironment.applyLocalLoginShellPath(
        env,
        hostBasePath: '/sparse/bin',
        posixDesktop: true,
        candidateDirs: const [],
      );
      expect(env['PATH'], '/skill/bin:/home/.nvm/bin:/sparse/bin');
    });

    test('unresolved: appends existing missing candidates only', () {
      final env = {'PATH': '/sparse/bin:$candidateA'};
      PtyLaunchEnvironment.applyLocalLoginShellPath(
        env,
        hostBasePath: '/sparse/bin',
        posixDesktop: true,
        candidateDirs: [candidateA, candidateB],
      );
      expect(env['PATH'], '/sparse/bin:$candidateA:$candidateB');
    });

    test('skips candidates that do not exist', () {
      final env = {'PATH': '/sparse/bin'};
      PtyLaunchEnvironment.applyLocalLoginShellPath(
        env,
        hostBasePath: '/sparse/bin',
        posixDesktop: true,
        candidateDirs: ['/does/not/exist', candidateB],
      );
      expect(env['PATH'], '/sparse/bin:$candidateB');
    });

    test('creates PATH when env had none and host base empty', () {
      final env = <String, String>{};
      PtyLaunchEnvironment.applyLocalLoginShellPath(
        env,
        hostBasePath: '',
        posixDesktop: true,
        candidateDirs: [candidateA],
      );
      expect(env['PATH'], candidateA);
    });

    test('no-op when not a POSIX desktop', () {
      final env = {'PATH': '/keep'};
      PtyLaunchEnvironment.applyLocalLoginShellPath(
        env,
        hostBasePath: '/keep',
        posixDesktop: false,
        candidateDirs: [candidateA],
      );
      expect(env['PATH'], '/keep');
    });
  });

  test(
    'buildPtyEnvironment keeps inherited env untouched for SSH even when a '
    'login-shell PATH is cached',
    () {
      HostShellPathResolver.debugSetCachedPath('/nvm/bin');
      addTearDown(HostShellPathResolver.resetForTest);
      final env = PtyLaunchEnvironment.buildPtyEnvironment(
        const {'FOO': 'bar'},
        inheritHostEnvironment: false,
      );
      expect(env.containsKey('PATH'), isFalse);
    },
  );

  test(
    'buildPtyEnvironment applies login-shell PATH for local POSIX launches',
    () {
      HostShellPathResolver.debugSetCachedPath('/nvm/bin');
      addTearDown(HostShellPathResolver.resetForTest);
      final env = PtyLaunchEnvironment.buildPtyEnvironment(
        const {'FOO': 'bar'},
        inheritHostEnvironment: true,
      );
      // On macOS/Linux hosts the merged PATH must contain the resolved dir;
      // on other hosts this test would be skipped by the platform gate, so
      // guard explicitly.
      if (!Platform.isMacOS && !Platform.isLinux) return;
      expect(env['PATH'], contains('/nvm/bin'));
    },
  );
}
