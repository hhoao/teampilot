import 'package:acpd/acpd.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/codex/capabilities/acp.dart';

Map<String, String> _env(
  CodexAcpCapability cap, {
  Map<String, String> baseEnv = const {},
}) => cap.buildEnvironment(
  sessionToolDir: '/runtime/s1/codex',
  workingDirectory: '/work',
  baseEnv: baseEnv,
);

void main() {
  test('launch argv is the adapter alone, not codex --acp', () {
    const cap = CodexAcpCapability();
    final exe = cap.agentExecutable('/usr/bin/codex');
    expect(exe, 'codex-acp');
    expect(cap.launchArgCandidates(exe), [
      ['codex-acp'],
    ]);
  });

  test('agentExecutable uses locateAdapter and ignores cli path as argv', () {
    final cap = CodexAcpCapability(
      locateAdapter: (cli) {
        expect(cli, '/usr/bin/codex');
        return '/opt/adapter/codex-acp';
      },
    );
    expect(cap.agentExecutable('/usr/bin/codex'), '/opt/adapter/codex-acp');
    expect(cap.launchArgCandidates('/opt/adapter/codex-acp'), [
      ['/opt/adapter/codex-acp'],
    ]);
  });

  test('api key provider injects both key names and isolates CODEX_HOME', () {
    final cap = CodexAcpCapability(
      authSource: () => const CodexAcpAuth(apiKey: 'sk-test'),
      codexPathSource: () => '/usr/bin/codex',
    );
    final env = _env(cap, baseEnv: const {'HOME': '/home/me', 'PATH': '/bin'});
    expect(env['OPENAI_API_KEY'], 'sk-test');
    expect(env['CODEX_API_KEY'], 'sk-test');
    expect(env['CODEX_HOME'], '/runtime/s1/codex');
    expect(env['CODEX_PATH'], '/usr/bin/codex');
    expect(env['HOME'], '/home/me');
    expect(env.containsKey('SURFACE'), isFalse);
    expect(env.containsKey('INITIAL_AGENT_MODE'), isFalse);
  });

  test('official blanks keys even when auth or parent env has them', () {
    final cap = CodexAcpCapability(
      authSource: () =>
          const CodexAcpAuth(official: true, apiKey: 'should-not-leak'),
      codexPathSource: () => '/usr/bin/codex',
    );
    final env = _env(
      cap,
      baseEnv: const {
        'OPENAI_API_KEY': 'parent-key',
        'CODEX_API_KEY': 'parent-key',
        'CODEX_HOME': '/runtime/s1/codex',
      },
    );
    expect(env['OPENAI_API_KEY'], '');
    expect(env['CODEX_API_KEY'], '');
    expect(env['CODEX_HOME'], '/runtime/s1/codex');
    expect(env['CODEX_PATH'], '/usr/bin/codex');
  });

  test('PROXY_MANAGED is not injected as a real API key', () {
    final cap = CodexAcpCapability(
      authSource: () => const CodexAcpAuth(apiKey: 'PROXY_MANAGED'),
    );
    final env = _env(cap);
    expect(env['OPENAI_API_KEY'], '');
    expect(env['CODEX_API_KEY'], '');
  });

  test(
    'no auth source blanks keys and sets CODEX_HOME plus default CODEX_PATH',
    () {
      const cap = CodexAcpCapability();
      final env = _env(cap, baseEnv: const {'A': 'b'});
      expect(env['A'], 'b');
      expect(env['CODEX_HOME'], '/runtime/s1/codex');
      expect(env['CODEX_PATH'], 'codex');
      expect(env['OPENAI_API_KEY'], '');
      expect(env['CODEX_API_KEY'], '');
    },
  );

  test('does not nest another /codex under sessionToolDir', () {
    const cap = CodexAcpCapability();
    final env = _env(cap);
    expect(env['CODEX_HOME'], '/runtime/s1/codex');
    expect(env['CODEX_HOME']!.endsWith('/codex/codex'), isFalse);
  });

  test('authenticateMethodId is null and translator has no extra methods', () {
    const cap = CodexAcpCapability();
    expect(cap.authenticateMethodId, isNull);
    expect(cap.translator.blockingClientMethods, isEmpty);
    expect(cap.translator.notificationClientMethods, isEmpty);
  });

  test('translator formats RpcError without abort mapping', () {
    const cap = CodexAcpCapability();
    expect(cap.translator, isA<CodexAcpTranslator>());
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
