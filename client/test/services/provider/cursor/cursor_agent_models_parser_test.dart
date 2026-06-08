import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/provider/cursor/cursor_agent_models_parser.dart';

void main() {
  const sample = '''
Available models

auto - Auto
gpt-5.2 - GPT-5.2
composer-2.5-fast - Composer 2.5 Fast (current, default)

Tip: use --model <id> (or /model <id> in interactive mode) to switch.
''';

  test('parseCursorAgentModelsOutput extracts ids', () {
    expect(
      parseCursorAgentModelsOutput(sample),
      ['auto', 'gpt-5.2', 'composer-2.5-fast'],
    );
  });

  test('parseCursorAgentDefaultModelId reads current default', () {
    expect(parseCursorAgentDefaultModelId(sample), 'composer-2.5-fast');
  });
}
