import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/utils/app_provider_model_candidates.dart';

void main() {
  test('includes defaultModel and config models map entries', () {
    const provider = AppProviderConfig(
      id: 'deepseek',
      cli: AppProviderCli.claude,
      name: 'DeepSeek',
      defaultModel: 'deepseek-v4-pro',
      config: {
        'models': {
          'alt-model': {
            'name': 'Alt Name',
            'model': 'deepseek-chat',
          },
        },
      },
    );

    expect(
      collectClaudeModelCandidates(provider),
      ['Alt Name', 'deepseek-chat', 'deepseek-v4-pro'],
    );
  });

  test('appends currentModel when not already listed', () {
    const provider = AppProviderConfig(
      id: 'custom',
      cli: AppProviderCli.claude,
      name: 'Custom',
      defaultModel: 'preset-model',
    );

    expect(
      collectClaudeModelCandidates(provider, currentModel: 'imported-model'),
      ['imported-model', 'preset-model'],
    );
  });

  test('returns empty list when provider has no model sources', () {
    const provider = AppProviderConfig(
      id: 'claude-official',
      cli: AppProviderCli.claude,
      name: 'Claude Official',
    );

    expect(collectClaudeModelCandidates(provider), isEmpty);
  });
}