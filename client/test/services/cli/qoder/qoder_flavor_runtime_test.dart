import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/hook_event.dart';
import 'package:teampilot/services/cli/qoder/capabilities/headless.dart';
import 'package:teampilot/services/cli/qoder/capabilities/history/ai_history_capability.dart';
import 'package:teampilot/services/cli/qoder/capabilities/hook_writer.dart';
import 'package:teampilot/services/cli/qoder/capabilities/prompt.dart';
import 'package:teampilot/services/cli/qoder/qoder_flavor.dart';

void main() {
  test('global flavor keeps the qoder runtime identity', () {
    const prompt = QoderPromptCapability();
    expect(prompt.toolId, 'qoder');
    expect(prompt.providerId, 'qoder');

    const history = QoderAiHistoryCapability();
    expect(history.adapter.id, 'qoder');
    expect(history.tailFallbackPrefix, 'qoder');

    const writer = QoderHookWriter();
    expect(writer.nativeEvent(HookEvent.sessionStart), 'SessionStart');
  });

  test('headless executable is resolved from the flavor', () {
    const cap = QoderHeadlessCapability(flavor: QoderFlavor.global);
    expect(cap.executable, 'qodercli');
  });
}
