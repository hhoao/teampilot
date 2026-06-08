import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/registry/capabilities/provider_form_capability.dart';
import 'package:teampilot/services/provider/codex/codex_provider_form_capability.dart';

void main() {
  const capability = CodexProviderFormCapability();

  group('CodexProviderFormCapability', () {
    test('buildConfig writes model_reasoning_effort when set', () {
      final config = capability.buildConfig(
        const ProviderFormInput(
          baseUrl: '',
          defaultModel: '',
          apiKeyField: 'OPENAI_API_KEY',
          config: {'auth': <String, Object?>{}},
          extra: {CodexFormExtraKeys.effort: 'high'},
        ),
      );

      expect(config['model_reasoning_effort'], 'high');
    });

    test('buildConfig removes model_reasoning_effort when effort empty', () {
      final config = capability.buildConfig(
        ProviderFormInput(
          baseUrl: '',
          defaultModel: '',
          apiKeyField: 'OPENAI_API_KEY',
          config: {
            'auth': <String, Object?>{},
            'model_reasoning_effort': 'medium',
          },
          extra: const {CodexFormExtraKeys.effort: ''},
        ),
      );

      expect(config.containsKey('model_reasoning_effort'), isFalse);
    });
  });
}
