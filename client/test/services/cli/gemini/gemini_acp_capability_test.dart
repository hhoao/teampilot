import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/gemini/capabilities/acp.dart';

void main() {
  test('launchArgCandidates puts one flag after executable per candidate', () {
    const cap = GeminiAcpCapability();
    expect(cap.launchArgCandidates('/usr/bin/gemini'), [
      ['/usr/bin/gemini', '--acp'],
      ['/usr/bin/gemini', '--experimental-acp'],
    ]);
  });

  test('buildEnvironment isolates config and injects key + surface', () {
    String? key() => 'test-key';
    final cap = GeminiAcpCapability(credentialSource: key);
    final env = cap.buildEnvironment(
      sessionToolDir: '/runtime/sessions/s1/tools',
      workingDirectory: '/work',
      baseEnv: const {'HOME': '/home/me'},
    );
    expect(env['GEMINI_CONFIG_DIR'], '/runtime/sessions/s1/tools/gemini');
    expect(env['GEMINI_API_KEY'], 'test-key');
    expect(env['SURFACE'], 'teampilot');
    expect(env.containsKey('HOME'), isTrue, reason: 'base env preserved');
  });

  test('buildEnvironment omits key when source returns null', () {
    String? key() => null;
    final cap = GeminiAcpCapability(credentialSource: key);
    final env = cap.buildEnvironment(
      sessionToolDir: '/d',
      workingDirectory: '/w',
      baseEnv: const {},
    );
    expect(env.containsKey('GEMINI_API_KEY'), isFalse);
  });

  test('exposes the gemini translator', () {
    const cap = GeminiAcpCapability();
    expect(cap.translator, isA<GeminiAcpTranslator>());
    expect(cap.translator.flagCandidates, const [
      '--acp',
      '--experimental-acp',
    ]);
  });

  test('agentExecutable is the gemini binary', () {
    const cap = GeminiAcpCapability();
    expect(cap.agentExecutable('/usr/bin/gemini'), '/usr/bin/gemini');
  });
}
