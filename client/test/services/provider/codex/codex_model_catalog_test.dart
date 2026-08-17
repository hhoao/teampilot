import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/services/cli/codex/provider/codex_model_catalog.dart';

void main() {
  test('official catalog includes current Codex and GPT models', () {
    const official = AppProviderConfig(
      id: 'openai-official',
      cli: CliTool.codex,
      name: 'OpenAI Official',
      category: AppProviderCategory.official,
      isOfficial: true,
    );

    final models = CodexModelCatalog.knownModelsForProvider(official);
    expect(models, contains('gpt-5.6-luna'));
    expect(models, contains('gpt-5.6-sol'));
    expect(models, contains('gpt-5.6-terra'));
    expect(models, contains('gpt-5.3-codex'));
  });

  test('proxy provider has no built-in Codex catalog', () {
    const proxy = AppProviderConfig(
      id: 'custom-proxy',
      cli: CliTool.codex,
      name: 'Proxy',
      apiKey: 'secret',
    );

    expect(CodexModelCatalog.knownModelsForProvider(proxy), isEmpty);
  });
}
