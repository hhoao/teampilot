import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/pty_launch_environment.dart';
import 'package:teampilot/services/terminal_session.dart';

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
}
