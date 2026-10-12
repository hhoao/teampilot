import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/cursor/capabilities/acp.dart';
import 'package:teampilot/services/cli/cursor/provider/cursor_launch_environment.dart';

void main() {
  test('launchArgCandidates is cursor-agent acp', () {
    const cap = CursorAcpCapability();
    expect(cap.launchArgCandidates('/usr/bin/cursor-agent'), [
      ['/usr/bin/cursor-agent', 'acp'],
    ]);
    expect(cap.agentExecutable('/usr/bin/cursor-agent'), '/usr/bin/cursor-agent');
    expect(cap.authenticateMethodId, 'cursor_login');
  });

  test('buildEnvironment preserves HOME and CURSOR_CONFIG_DIR from baseEnv', () {
    const cap = CursorAcpCapability();
    final env = cap.buildEnvironment(
      sessionToolDir: '/runtime/cursor',
      workingDirectory: '/work',
      baseEnv: {
        'PATH': '/bin',
        'HOME': '/iso/home',
        'CURSOR_CONFIG_DIR': '/iso/home/.cursor',
        CursorLaunchEnvironment.credentialStoreEnvKey:
            CursorLaunchEnvironment.credentialStoreFile,
      },
    );
    expect(env['HOME'], '/iso/home');
    expect(env['CURSOR_CONFIG_DIR'], '/iso/home/.cursor');
    expect(env['PATH'], '/bin');
    expect(env.containsKey('CURSOR_API_KEY'), isFalse);
  });

  test('buildEnvironment does not invent HOME from sessionToolDir', () {
    const cap = CursorAcpCapability();
    final env = cap.buildEnvironment(
      sessionToolDir: '/runtime/cursor',
      workingDirectory: '/work',
      baseEnv: const {'PATH': '/bin'},
    );
    expect(env['HOME'], isNull);
    expect(env['CURSOR_CONFIG_DIR'], isNull);
    expect(env['PATH'], '/bin');
  });

  test('translator lists Cursor client extension methods', () {
    const cap = CursorAcpCapability();
    expect(cap.translator, isA<CursorAcpTranslator>());
    expect(cap.translator.blockingClientMethods, [
      'cursor/ask_question',
      'cursor/create_plan',
    ]);
    expect(cap.translator.notificationClientMethods, [
      'cursor/update_todos',
      'cursor/task',
      'cursor/generate_image',
    ]);
    expect(cap.translator.flagCandidates, isEmpty);
  });
}
