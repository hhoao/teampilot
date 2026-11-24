import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/codex/provider/codex_context_window_toml.dart';

void main() {
  test('applyContextWindow replaces an existing line', () {
    const input = '''
model = "gpt-5.4"
model_context_window = 128000
''';
    final out = CodexContextWindowToml.applyContextWindow(input, 200000);
    expect(out, contains('model_context_window = 200000'));
    expect(out, isNot(contains('model_context_window = 128000')));
  });

  test('applyContextWindow inserts after the model line', () {
    const input = 'model = "gpt-5.4"';
    final out = CodexContextWindowToml.applyContextWindow(input, 300000);
    expect(out, contains('model = "gpt-5.4"'));
    expect(out, contains('model_context_window = 300000'));
  });

  test('applyContextWindow appends to an empty body', () {
    expect(
      CodexContextWindowToml.applyContextWindow('', 200000),
      'model_context_window = 200000',
    );
  });

  test('applyContextWindow ignores non-positive values', () {
    const input = 'model = "gpt-5.4"';
    expect(CodexContextWindowToml.applyContextWindow(input, 0), input);
  });
}
