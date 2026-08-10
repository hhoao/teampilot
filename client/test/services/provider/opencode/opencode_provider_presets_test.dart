import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/services/cli/opencode/provider_presets.dart';

void main() {
  test('opencode-go resolves as an official subscription preset', () {
    final preset = OpencodeProviderPresets.byId('opencode-go');
    expect(preset, isNotNull);
    expect(preset!.label, 'OpenCode Go (subscription)');
    expect(preset.template.isOfficial, isTrue);
    expect(preset.template.category, AppProviderCategory.official);
    expect(preset.template.apiKeyUrl, 'https://opencode.ai/go');
    expect(preset.template.baseUrl, 'https://opencode.ai/zen/go/v1');
    expect(preset.template.defaultModel, 'deepseek-v4-flash');
    expect(preset.template.config['npm'], '@ai-sdk/openai-compatible');
  });
}
