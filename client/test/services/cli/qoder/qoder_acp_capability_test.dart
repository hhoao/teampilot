import 'package:acpd/acpd.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/acp/acp_agent_translator.dart';
import 'package:teampilot/services/cli/qoder/capabilities/acp.dart';

void main() {
  test('launchArgCandidates is `qodercli --acp`', () {
    const cap = QoderAcpCapability();
    expect(cap.launchArgCandidates('/usr/bin/qodercli'), [
      ['/usr/bin/qodercli', '--acp'],
    ]);
  });

  test('isolates QODER_CONFIG_DIR and keeps base env', () {
    const cap = QoderAcpCapability();
    final env = cap.buildEnvironment(
      sessionToolDir: '/runtime/sessions/s1/qoder',
      workingDirectory: '/work',
      baseEnv: const {'HOME': '/home/me'},
    );
    expect(env['QODER_CONFIG_DIR'], '/runtime/sessions/s1/qoder');
    expect(env['HOME'], '/home/me');
  });

  test('never calls authenticate', () async {
    const cap = QoderAcpCapability();
    expect(cap.authenticateMethodId, isNull);
    expect(await cap.resolveAuthenticateMethodId({'HOME': '/x'}), isNull);
  });

  test('MCP is config-only', () {
    const cap = QoderAcpCapability();
    expect(cap.forwardSessionNewMcpServers, isFalse);
    expect(cap.sessionNewMeta(const {}), isEmpty);
  });

  test('auth-required RPC maps to the sign-in sentinel', () {
    const translator = QoderAcpTranslator();
    expect(
      translator.translateStopError(
        RpcError(
          code: ErrorCode.authRequired.code,
          message: 'Authentication required',
        ),
        suppressAbort: false,
      ),
      acpStopAuthRequired,
    );
  });
}
