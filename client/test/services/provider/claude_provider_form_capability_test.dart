import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/registry/capabilities/provider_form_capability.dart';
import 'package:teampilot/services/provider/claude/claude_provider_form_capability.dart';

void main() {
  const capability = ClaudeProviderFormCapability();

  group('ClaudeProviderFormCapability', () {
    test('buildConfig does not freeze derived endpoint/model/credential env', () {
      final config = capability.buildConfig(
        const ProviderFormInput(
          baseUrl: 'https://api.example.com',
          defaultModel: 'claude-sonnet',
          apiKeyField: 'ANTHROPIC_API_KEY',
          config: {'env': <String, Object?>{}},
          extra: {},
        ),
      );

      final env = config['env'] as Map<String, Object?>;
      // Endpoint/model/credential live on canonical top-level fields and are
      // materialized at launch (see buildClaudeSettings) — the form must not
      // bake any derived env or the duplicate api_key_field into the record.
      expect(env.containsKey('ANTHROPIC_BASE_URL'), isFalse);
      expect(env.containsKey('ANTHROPIC_MODEL'), isFalse);
      expect(env.containsKey('ANTHROPIC_DEFAULT_HAIKU_MODEL'), isFalse);
      expect(config.containsKey('api_key_field'), isFalse);
      // apiFormat was dead config (never consumed at launch) and was removed.
      expect(config.containsKey('apiFormat'), isFalse);
    });

    test('buildConfig preserves user-authored custom env keys', () {
      final config = capability.buildConfig(
        ProviderFormInput(
          baseUrl: 'https://api.example.com',
          defaultModel: 'claude-sonnet',
          apiKeyField: 'ANTHROPIC_AUTH_TOKEN',
          config: {
            'env': {'DISABLE_AUTOUPDATER': '1'},
          },
          extra: const {},
        ),
      );

      final env = config['env'] as Map<String, Object?>;
      expect(env['DISABLE_AUTOUPDATER'], '1');
    });

    test('normalizeApiKeyField falls back for unknown values', () {
      expect(capability.normalizeApiKeyField('ANTHROPIC_API_KEY'), 'ANTHROPIC_API_KEY');
      expect(capability.normalizeApiKeyField('invalid'), 'ANTHROPIC_AUTH_TOKEN');
      expect(capability.normalizeApiKeyField(null), 'ANTHROPIC_AUTH_TOKEN');
    });
  });
}
