import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/registry/capabilities/provider_form_capability.dart';
import 'package:teampilot/services/provider/claude/claude_provider_form_capability.dart';

void main() {
  const capability = ClaudeProviderFormCapability();

  group('ClaudeProviderFormCapability', () {
    test('buildConfig writes env aliases and api format', () {
      final config = capability.buildConfig(
        const ProviderFormInput(
          baseUrl: 'https://api.example.com',
          defaultModel: 'claude-sonnet',
          apiKeyField: 'ANTHROPIC_API_KEY',
          config: {'env': <String, Object?>{}},
          extra: {
            ClaudeFormExtraKeys.apiFormat: 'openai_chat',
            ClaudeFormExtraKeys.haikuModel: 'haiku-1',
            ClaudeFormExtraKeys.sonnetModel: 'sonnet-1',
            ClaudeFormExtraKeys.opusModel: 'opus-1',
          },
        ),
      );

      final env = config['env'] as Map<String, Object?>;
      expect(env['ANTHROPIC_BASE_URL'], 'https://api.example.com');
      expect(env['ANTHROPIC_MODEL'], 'claude-sonnet');
      expect(env['ANTHROPIC_DEFAULT_HAIKU_MODEL'], 'haiku-1');
      expect(env['ANTHROPIC_DEFAULT_SONNET_MODEL'], 'sonnet-1');
      expect(env['ANTHROPIC_DEFAULT_OPUS_MODEL'], 'opus-1');
      expect(config['apiFormat'], 'openai_chat');
      expect(config['api_key_field'], 'ANTHROPIC_API_KEY');
    });

    test('buildConfig removes empty env entries', () {
      final config = capability.buildConfig(
        ProviderFormInput(
          baseUrl: '',
          defaultModel: '',
          apiKeyField: 'ANTHROPIC_AUTH_TOKEN',
          config: {
            'env': {
              'ANTHROPIC_BASE_URL': 'https://old.example',
              'ANTHROPIC_DEFAULT_HAIKU_MODEL': 'old-haiku',
            },
          },
          extra: const {},
        ),
      );

      final env = config['env'] as Map<String, Object?>;
      expect(env.containsKey('ANTHROPIC_BASE_URL'), isFalse);
      expect(env.containsKey('ANTHROPIC_MODEL'), isFalse);
      expect(env.containsKey('ANTHROPIC_DEFAULT_HAIKU_MODEL'), isFalse);
    });

    test('normalizeApiKeyField falls back for unknown values', () {
      expect(capability.normalizeApiKeyField('ANTHROPIC_API_KEY'), 'ANTHROPIC_API_KEY');
      expect(capability.normalizeApiKeyField('invalid'), 'ANTHROPIC_AUTH_TOKEN');
      expect(capability.normalizeApiKeyField(null), 'ANTHROPIC_AUTH_TOKEN');
    });
  });
}
