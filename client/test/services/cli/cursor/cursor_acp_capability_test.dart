import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/cli/cursor/capabilities/acp.dart';
import 'package:teampilot/services/cli/cursor/provider/cursor_home_layout.dart';
import 'package:teampilot/services/cli/cursor/provider/cursor_launch_environment.dart';
import 'package:teampilot/services/io/filesystem.dart';

import '../../../support/in_memory_filesystem.dart';

const _loggedInAuth = '{"accessToken":"at1","refreshToken":"rt1"}';
const _loggedOutAuth = '{"accessToken":"","refreshToken":""}';

CursorAcpCapability _linuxCap(Filesystem fs) =>
    CursorAcpCapability(fs: fs, platform: CursorHomePlatform.linux);

String _linuxAuthPath(String home) =>
    CursorHomeLayout(
      pathContext: p.Context(style: p.Style.posix),
      platform: CursorHomePlatform.linux,
    ).authJson(home);

void main() {
  test('launchArgCandidates is cursor-agent acp', () {
    const cap = CursorAcpCapability();
    expect(cap.launchArgCandidates('/usr/bin/cursor-agent'), [
      ['/usr/bin/cursor-agent', 'acp'],
    ]);
    expect(
      cap.agentExecutable('/usr/bin/cursor-agent'),
      '/usr/bin/cursor-agent',
    );
    expect(cap.authenticateMethodId, 'cursor_login');
    expect(cap.forwardSessionNewMcpServers, isFalse);
  });

  test(
    'buildEnvironment preserves HOME and CURSOR_CONFIG_DIR from baseEnv',
    () {
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
    },
  );

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

  test(
    'resolveAuthenticateMethodId skips cursor_login when auth.json has tokens',
    () async {
      final fs = InMemoryFilesystem(
        pathContext: p.Context(style: p.Style.posix),
      );
      const home = '/iso/home';
      await fs.writeString(_linuxAuthPath(home), _loggedInAuth);
      final cap = _linuxCap(fs);
      expect(cap.authenticateMethodId, 'cursor_login');
      expect(await cap.resolveAuthenticateMethodId({'HOME': home}), isNull);
    },
  );

  test(
    'resolveAuthenticateMethodId sends cursor_login when auth.json is missing',
    () async {
      final fs = InMemoryFilesystem(
        pathContext: p.Context(style: p.Style.posix),
      );
      final cap = _linuxCap(fs);
      expect(
        await cap.resolveAuthenticateMethodId({'HOME': '/iso/home'}),
        'cursor_login',
      );
    },
  );

  test(
    'resolveAuthenticateMethodId sends cursor_login when tokens are empty',
    () async {
      final fs = InMemoryFilesystem(
        pathContext: p.Context(style: p.Style.posix),
      );
      const home = '/iso/home';
      await fs.writeString(_linuxAuthPath(home), _loggedOutAuth);
      final cap = _linuxCap(fs);
      expect(
        await cap.resolveAuthenticateMethodId({'HOME': home}),
        'cursor_login',
      );
    },
  );

  test(
    'resolveAuthenticateMethodId sends cursor_login when HOME is empty',
    () async {
      final fs = InMemoryFilesystem(
        pathContext: p.Context(style: p.Style.posix),
      );
      final cap = _linuxCap(fs);
      expect(await cap.resolveAuthenticateMethodId(const {}), 'cursor_login');
      expect(
        await cap.resolveAuthenticateMethodId({'HOME': '  '}),
        'cursor_login',
      );
    },
  );

  test(
    'resolveAuthenticateMethodId falls back to USERPROFILE when HOME is absent',
    () async {
      final fs = InMemoryFilesystem(
        pathContext: p.Context(style: p.Style.posix),
      );
      const home = '/iso/home';
      await fs.writeString(_linuxAuthPath(home), _loggedInAuth);
      final cap = _linuxCap(fs);
      expect(
        await cap.resolveAuthenticateMethodId({'USERPROFILE': home}),
        isNull,
      );
    },
  );
}
