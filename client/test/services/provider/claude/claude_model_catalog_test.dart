import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/services/provider/claude/claude_model_catalog.dart';

void main() {
  test('official catalog includes aliases and frontier model ids', () {
    const official = AppProviderConfig(
      id: 'claude-official',
      cli: CliTool.claude,
      name: 'Claude Official',
      category: AppProviderCategory.official,
      isOfficial: true,
      config: {'env': {}},
    );

    final models = ClaudeModelCatalog.knownModelsForProvider(official);
    expect(models, contains('sonnet'));
    expect(models, contains('opus'));
    expect(models, contains('claude-sonnet-4-6'));
    expect(models, contains('claude-opus-4-7'));
  });

  test('proxy provider has no built-in catalog', () {
    const proxy = AppProviderConfig(
      id: 'custom-proxy',
      cli: CliTool.claude,
      name: 'Proxy',
      defaultModel: 'deepseek-chat',
    );

    expect(ClaudeModelCatalog.knownModelsForProvider(proxy), isEmpty);
  });
}
