import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/terminal/pty_launch_environment.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';

void main() {
  test('buildPtyEnvironment injects TERM_PROGRAM and VTE_VERSION', () {
    final env = TerminalSession.buildPtyEnvironment(const {'FOO': 'bar'});
    expect(env['TERM_PROGRAM'], PtyLaunchEnvironment.termProgram);
    expect(env['VTE_VERSION'], PtyLaunchEnvironment.vteVersion);
    expect(env['FOO'], 'bar');
  });

  test('buildPtyEnvironment does not override explicit TERM_PROGRAM', () {
    final env = TerminalSession.buildPtyEnvironment(
      const {'TERM_PROGRAM': 'custom'},
    );
    expect(env['TERM_PROGRAM'], 'custom');
    expect(env['VTE_VERSION'], PtyLaunchEnvironment.vteVersion);
  });

  test('buildPtyEnvironment leaves COLORFGBG untouched when no theme is given', () {
    final env = TerminalSession.buildPtyEnvironment(const {});
    // No theme → we neither add nor rewrite it; it stays whatever was inherited.
    expect(env['COLORFGBG'], Platform.environment['COLORFGBG']);
  });

  test('buildPtyEnvironment maps a dark theme background to COLORFGBG 15;0', () {
    final env = TerminalSession.buildPtyEnvironment(
      const {},
      themeBackground: 0x0A0C10,
    );
    expect(env['COLORFGBG'], '15;0');
  });

  test('buildPtyEnvironment maps a light theme background to COLORFGBG 0;15', () {
    final env = TerminalSession.buildPtyEnvironment(
      const {},
      themeBackground: 0xF7F9FC,
    );
    expect(env['COLORFGBG'], '0;15');
  });

  test('applyColorScheme overrides an inherited COLORFGBG with the embedded bg', () {
    final env = <String, String>{'COLORFGBG': '0;15'}; // host says light
    PtyLaunchEnvironment.applyColorScheme(env, background: 0x0A0C10); // we are dark
    expect(env['COLORFGBG'], '15;0');
  });

  test(
    'buildPtyEnvironment omits host Platform.environment for SSH remote launches',
    () {
      final env = TerminalSession.buildPtyEnvironment(
        const {'CLAUDE_CONFIG_DIR': '/tmp/claude'},
        inheritHostEnvironment: false,
      );
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
}
