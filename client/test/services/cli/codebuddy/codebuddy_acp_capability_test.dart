import 'package:acpd/acpd.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/acp/acp_agent_translator.dart';
import 'package:teampilot/services/cli/codebuddy/capabilities/acp.dart';

void main() {
  test('launchArgCandidates is `codebuddy --acp`', () {
    const cap = CodebuddyAcpCapability();
    expect(cap.launchArgCandidates('/usr/bin/codebuddy'), [
      ['/usr/bin/codebuddy', '--acp'],
    ]);
  });

  test('agentExecutable is the CLI binary (no separate adapter)', () {
    const cap = CodebuddyAcpCapability();
    expect(cap.agentExecutable('/usr/bin/codebuddy'), '/usr/bin/codebuddy');
  });

  test('buildEnvironment isolates CODEBUDDY_CONFIG_DIR and keeps base env', () {
    const cap = CodebuddyAcpCapability();
    final env = cap.buildEnvironment(
      sessionToolDir: '/runtime/sessions/s1/codebuddy',
      workingDirectory: '/work',
      baseEnv: const {'HOME': '/home/me'},
    );
    expect(env['CODEBUDDY_CONFIG_DIR'], '/runtime/sessions/s1/codebuddy');
    expect(env['HOME'], '/home/me', reason: 'base env preserved');
    expect(env.containsKey('SURFACE'), isFalse);
  });

  test('does not authenticate: existing CLI login is reused', () async {
    const cap = CodebuddyAcpCapability();
    expect(cap.authenticateMethodId, isNull);
    expect(await cap.resolveAuthenticateMethodId({'HOME': '/x'}), isNull);
  });

  test('MCP is config-only (no session/new forwarding)', () {
    const cap = CodebuddyAcpCapability();
    expect(cap.forwardSessionNewMcpServers, isFalse);
    expect(cap.sessionNewMeta(const {}), isEmpty);
  });

  test('exposes the codebuddy translator', () {
    const cap = CodebuddyAcpCapability();
    expect(cap.translator, isA<CodebuddyAcpTranslator>());
    expect(cap.translator.flagCandidates, const ['--acp']);
    expect(cap.translator.blockingClientMethods, isEmpty);
    expect(cap.translator.notificationClientMethods, const [
      '_codebuddy.ai/command',
      '_codebuddy.ai/modResidentInvalidate',
    ]);
  });

  test('maps auth_required errors to the not-logged-in sentinel', () {
    const translator = CodebuddyAcpTranslator();
    final translated = translator.translateStopError(
      RpcError(
        code: ErrorCode.authRequired.code,
        message: 'Authentication required',
      ),
      suppressAbort: true,
    );
    expect(translated, acpStopAuthRequired);
  });

  test('keeps other RPC errors readable', () {
    const translator = CodebuddyAcpTranslator();
    final translated = translator.translateStopError(
      RpcError(code: ErrorCode.internalError.code, message: 'boom'),
      suppressAbort: true,
    );
    expect(translated, contains('ACP error'));
    expect(translated, contains('boom'));
  });

  test(
    'refusal meta with an auth error maps to the not-logged-in sentinel',
    () {
      const translator = CodebuddyAcpTranslator();
      expect(
        translator.translateStopMeta(StopReason.refusal, const {
          'codebuddy.ai/errorMessage':
              '{"code":-32000,"message":"Authentication required"}',
        }),
        acpStopAuthRequired,
      );
      expect(
        translator.translateStopMeta(StopReason.refusal, const {
          'codebuddy.ai/errorMessage': '{"code":1,"message":"content policy"}',
        }),
        isNull,
      );
      expect(
        translator.translateStopMeta(StopReason.endTurn, const {}),
        isNull,
      );
    },
  );
}
