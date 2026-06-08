import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/provider/codex/codex_effort_toml.dart';

void main() {
  test('applyReasoningEffort replaces existing line', () {
    const input = '''
model = "gpt-5.4"
model_reasoning_effort = "high"
''';
    final out = CodexEffortToml.applyReasoningEffort(input, 'minimal');
    expect(out, contains('model_reasoning_effort = "minimal"'));
    expect(out, isNot(contains('model_reasoning_effort = "high"')));
  });

  test('applyReasoningEffort inserts after model line', () {
    const input = 'model = "gpt-5.4"';
    final out = CodexEffortToml.applyReasoningEffort(input, 'xhigh');
    expect(out, contains('model = "gpt-5.4"'));
    expect(out, contains('model_reasoning_effort = "xhigh"'));
  });
}
