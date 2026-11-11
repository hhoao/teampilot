import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/hook_event.dart';
import 'package:teampilot/services/cli/qoder/capabilities/acp.dart';
import 'package:teampilot/services/cli/qoder/capabilities/history/ai_history_capability.dart';
import 'package:teampilot/services/cli/qoder/capabilities/hook_writer.dart';
import 'package:teampilot/services/cli/qoder/capabilities/prompt.dart';
import 'package:teampilot/services/cli/qoder/qoder_flavor.dart';

void main() {
  test('CN ACP points the config dir at the CN env key', () {
    const cap = QoderAcpCapability(configDirEnvKey: 'QODERCN_CONFIG_DIR');
    final env = cap.buildEnvironment(
      sessionToolDir: '/runtime/s1/qoder-cn',
      workingDirectory: '/workspace/workspace',
    );
    expect(env['QODERCN_CONFIG_DIR'], '/runtime/s1/qoder-cn');
    expect(env.containsKey('QODER_CONFIG_DIR'), isFalse);
  });

  test('CN history seeds the session env with the CN config key', () {
    const cap = QoderAiHistoryCapability(flavor: QoderFlavor.cn);
    expect(cap.sessionEnv(toolRoot: '/runtime/s1/qoder-cn'), {
      'QODERCN_CONFIG_DIR': '/runtime/s1/qoder-cn',
    });
  });

  test('CN prompt uses the qoder-cn session tool id', () {
    const cap = QoderPromptCapability(flavor: QoderFlavor.cn);
    expect(cap.toolId, 'qoder-cn');
    expect(cap.providerId, 'qoder-cn');
  });

  test('CN history reports the CN identity', () {
    const cap = QoderAiHistoryCapability(flavor: QoderFlavor.cn);
    expect(cap.adapter.id, 'qoder-cn');
    expect(cap.tailFallbackPrefix, 'qoder-cn');
  });

  test('CN hook writer uses Claude-family event names', () {
    const cap = QoderHookWriter(flavor: QoderFlavor.cn);
    expect(cap.nativeEvent(HookEvent.sessionStart), 'SessionStart');
    expect(cap.nativeEvent(HookEvent.preToolUse), 'PreToolUse');
    expect(cap.nativeEvent(HookEvent.subagentStart), isNull);
  });
}
