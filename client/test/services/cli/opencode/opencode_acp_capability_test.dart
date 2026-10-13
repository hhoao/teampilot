import 'package:acpd/acpd.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/acp/acp_agent_translator.dart';
import 'package:teampilot/services/cli/opencode/capabilities/acp.dart';
import 'package:teampilot/services/cli/opencode/capabilities/provider.dart';

void main() {
  test('launchArgCandidates is opencode acp', () {
    const cap = OpencodeAcpCapability();
    expect(cap.launchArgCandidates('/usr/bin/opencode'), [
      ['/usr/bin/opencode', 'acp'],
    ]);
    expect(cap.agentExecutable('/usr/bin/opencode'), '/usr/bin/opencode');
    expect(cap.authenticateMethodId, isNull);
    expect(cap.forwardSessionNewMcpServers, isFalse);
  });

  test('buildEnvironment preserves OPENCODE_* keys from baseEnv', () {
    const cap = OpencodeAcpCapability();
    final env = cap.buildEnvironment(
      sessionToolDir: '/runtime/opencode',
      workingDirectory: '/work',
      baseEnv: {
        'PATH': '/bin',
        'HOME': '/iso/home',
        OpencodeProviderCapability.configDirEnv: '/iso/config',
        OpencodeProviderCapability.dbPathEnv: '/iso/config/opencode.db',
        OpencodeProviderCapability.authContentEnv: '{"anthropic":"secret"}',
        OpencodeProviderCapability.cliConfigContentEnv:
            OpencodeProviderCapability.cliConfigContent,
      },
    );
    expect(env['HOME'], '/iso/home');
    expect(env['PATH'], '/bin');
    expect(env[OpencodeProviderCapability.configDirEnv], '/iso/config');
    expect(
      env[OpencodeProviderCapability.dbPathEnv],
      '/iso/config/opencode.db',
    );
    expect(
      env[OpencodeProviderCapability.authContentEnv],
      '{"anthropic":"secret"}',
    );
    expect(
      env[OpencodeProviderCapability.cliConfigContentEnv],
      OpencodeProviderCapability.cliConfigContent,
    );
  });

  test('buildEnvironment does not invent HOME from sessionToolDir', () {
    const cap = OpencodeAcpCapability();
    final env = cap.buildEnvironment(
      sessionToolDir: '/runtime/opencode',
      workingDirectory: '/work',
      baseEnv: const {'PATH': '/bin'},
    );
    expect(env['HOME'], isNull);
    expect(env[OpencodeProviderCapability.configDirEnv], isNull);
    expect(env['PATH'], '/bin');
  });

  test('translator has no client extension methods', () {
    const cap = OpencodeAcpCapability();
    expect(cap.translator, isA<OpencodeAcpTranslator>());
    expect(cap.translator.flagCandidates, isEmpty);
    expect(cap.translator.blockingClientMethods, isEmpty);
    expect(cap.translator.notificationClientMethods, isEmpty);
  });

  test('translator maps authRequired to acpStopAuthRequired', () {
    const translator = OpencodeAcpTranslator();
    final error = RpcError.fromCode(ErrorCode.authRequired);
    expect(
      translator.translateStopError(error, suppressAbort: false),
      acpStopAuthRequired,
    );
  });

  test('translator leaves other RpcErrors as ACP error text', () {
    const translator = OpencodeAcpTranslator();
    final error = RpcError.fromCode(ErrorCode.internalError);
    expect(
      translator.translateStopError(error, suppressAbort: false),
      'ACP error ${ErrorCode.internalError.code}: ${error.message}',
    );
  });
}
