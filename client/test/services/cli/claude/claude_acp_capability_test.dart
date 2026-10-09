import 'dart:io';

import 'package:acpd/acpd.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/claude/capabilities/acp.dart';

Map<String, String> _env(
  ClaudeAcpCapability cap, {
  Map<String, String> baseEnv = const {},
}) => cap.buildEnvironment(
  sessionToolDir: '/runtime/s1/tools',
  workingDirectory: '/work',
  baseEnv: baseEnv,
);

void main() {
  test('launch argv is the adapter alone, not claude --acp', () {
    const cap = ClaudeAcpCapability();
    final exe = cap.agentExecutable('/usr/bin/claude');
    expect(exe, 'claude-agent-acp');
    expect(cap.launchArgCandidates(exe), [
      ['claude-agent-acp'],
    ]);
  });

  test('agentExecutable ignores the cli path via locateAdapter', () {
    final seen = <String>[];
    final cap = ClaudeAcpCapability(
      locateAdapter: (cli) {
        seen.add(cli);
        return '/opt/adapter/claude-agent-acp';
      },
    );
    expect(
      cap.agentExecutable('/usr/bin/claude'),
      '/opt/adapter/claude-agent-acp',
    );
    expect(seen, ['/usr/bin/claude']);
    expect(cap.launchArgCandidates('/opt/adapter/claude-agent-acp'), [
      ['/opt/adapter/claude-agent-acp'],
    ]);
  });

  test('api key provider injects ANTHROPIC_API_KEY and isolates config', () {
    final cap = ClaudeAcpCapability(
      authSource: () => const ClaudeAcpAuth(apiKey: 'sk-test'),
    );
    final env = _env(cap, baseEnv: const {'HOME': '/home/me'});
    expect(env['ANTHROPIC_API_KEY'], 'sk-test');
    expect(env['ANTHROPIC_AUTH_TOKEN'], '');
    expect(env['CLAUDE_CONFIG_DIR'], '/runtime/s1/tools/claude');
    expect(env['HOME'], '/home/me', reason: 'base env preserved');
    expect(env.containsKey('CCGUI_CLI_LOGIN_AUTHORIZED'), isFalse);
    expect(env.containsKey('SURFACE'), isFalse);
  });

  test('auth token provider injects ANTHROPIC_AUTH_TOKEN only', () {
    final cap = ClaudeAcpCapability(
      authSource: () => const ClaudeAcpAuth(authToken: 'tok'),
    );
    final env = _env(cap);
    expect(env['ANTHROPIC_AUTH_TOKEN'], 'tok');
    expect(env['ANTHROPIC_API_KEY'], '');
  });

  test('api key wins over auth token when both are set', () {
    final cap = ClaudeAcpCapability(
      authSource: () => const ClaudeAcpAuth(apiKey: 'k', authToken: 'tok'),
    );
    final env = _env(cap);
    expect(env['ANTHROPIC_API_KEY'], 'k');
    expect(env['ANTHROPIC_AUTH_TOKEN'], '');
  });

  test('official omits keys, flags login, and copies credentials', () {
    final copies = <List<String>>[];
    final cap = ClaudeAcpCapability(
      authSource: () => const ClaudeAcpAuth(
        official: true,
        apiKey: 'should-not-leak',
        authToken: 'should-not-leak',
        officialCredentialsPath: '/creds/.credentials.json',
      ),
      copyFile: (dest, src) => copies.add([dest, src]),
    );
    final env = _env(cap, baseEnv: const {'PATH': '/bin'});
    expect(env['ANTHROPIC_API_KEY'], '');
    expect(env['ANTHROPIC_AUTH_TOKEN'], '');
    expect(env['CCGUI_CLI_LOGIN_AUTHORIZED'], '1');
    expect(env['CLAUDE_CONFIG_DIR'], '/runtime/s1/tools/claude');
    expect(env['PATH'], '/bin');
    expect(copies, [
      [
        '/runtime/s1/tools/claude/.credentials.json',
        '/creds/.credentials.json',
      ],
    ]);
  });

  test('official without credentials path does not copy', () {
    var copied = false;
    final cap = ClaudeAcpCapability(
      authSource: () => const ClaudeAcpAuth(official: true),
      copyFile: (_, _) => copied = true,
    );
    final env = _env(cap);
    expect(env['CCGUI_CLI_LOGIN_AUTHORIZED'], '1');
    expect(copied, isFalse);
  });

  test('no auth source yields only config dir and base env', () {
    const cap = ClaudeAcpCapability();
    final env = _env(cap, baseEnv: const {'A': 'b'});
    expect(env, {
      'A': 'b',
      'CLAUDE_CONFIG_DIR': '/runtime/s1/tools/claude',
      'ANTHROPIC_API_KEY': '',
      'ANTHROPIC_AUTH_TOKEN': '',
      'ANTHROPIC_BASE_URL': '',
    });
  });

  test('official blanks inherited ANTHROPIC_* so Process.start overwrites', () {
    final cap = ClaudeAcpCapability(
      authSource: () => const ClaudeAcpAuth(
        official: true,
        apiKey: 'leak',
        authToken: 'leak',
        baseUrl: 'https://leak.example',
      ),
      copyFile: (_, _) {},
    );
    final env = _env(
      cap,
      baseEnv: const {
        'ANTHROPIC_API_KEY': 'parent-key',
        'ANTHROPIC_AUTH_TOKEN': 'parent-token',
        'ANTHROPIC_BASE_URL': 'https://parent.example',
      },
    );
    expect(env['ANTHROPIC_API_KEY'], '');
    expect(env['ANTHROPIC_AUTH_TOKEN'], '');
    expect(env['ANTHROPIC_BASE_URL'], '');
  });

  test('non-official sets ANTHROPIC_BASE_URL from auth', () {
    final cap = ClaudeAcpCapability(
      authSource: () => const ClaudeAcpAuth(
        authToken: 'tok',
        baseUrl: 'https://proxy.example/v1',
      ),
    );
    final env = _env(
      cap,
      baseEnv: const {'ANTHROPIC_BASE_URL': 'https://parent.example'},
    );
    expect(env['ANTHROPIC_BASE_URL'], 'https://proxy.example/v1');
    expect(env['ANTHROPIC_AUTH_TOKEN'], 'tok');
    expect(env['ANTHROPIC_API_KEY'], '');
  });

  group('default copyFile', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('acp_cap_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('creates claude dir and copies credentials', () {
      final src = File('${tmp.path}/src/.credentials.json')
        ..createSync(recursive: true)
        ..writeAsStringSync('{"oauth":1}');
      final cap = ClaudeAcpCapability(
        authSource: () => ClaudeAcpAuth(
          official: true,
          officialCredentialsPath: src.path,
        ),
      );
      final env = cap.buildEnvironment(
        sessionToolDir: '${tmp.path}/tools',
        workingDirectory: '/work',
      );
      expect(env['CLAUDE_CONFIG_DIR'], '${tmp.path}/tools/claude');
      final dest = File('${tmp.path}/tools/claude/.credentials.json');
      expect(dest.existsSync(), isTrue);
      expect(dest.readAsStringSync(), '{"oauth":1}');
    });

    test('missing source does not throw and leaves dir empty', () {
      final cap = ClaudeAcpCapability(
        authSource: () => ClaudeAcpAuth(
          official: true,
          officialCredentialsPath: '${tmp.path}/nope/.credentials.json',
        ),
      );
      final env = cap.buildEnvironment(
        sessionToolDir: '${tmp.path}/tools',
        workingDirectory: '/work',
      );
      expect(env['CCGUI_CLI_LOGIN_AUTHORIZED'], '1');
      expect(
        File('${tmp.path}/tools/claude/.credentials.json').existsSync(),
        isFalse,
      );
    });
  });

  test('translator formats RpcError without abort mapping', () {
    const cap = ClaudeAcpCapability();
    expect(cap.translator, isA<ClaudeAcpTranslator>());
    expect(cap.translator.flagCandidates, isEmpty);
    final abortLike = RpcError(
      code: ErrorCode.internalError.code,
      message: 'This operation was aborted',
    );
    expect(
      cap.translator.translateStopError(abortLike, suppressAbort: true),
      'ACP error ${ErrorCode.internalError.code}: This operation was aborted',
    );
    expect(
      cap.translator.translateStopError(StateError('x'), suppressAbort: false),
      StateError('x').toString(),
    );
  });
}
