import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/services/cli/claude/capabilities/provider.dart';
import 'package:teampilot/services/cli/registry/capabilities/provider_capability.dart';
import 'package:teampilot/services/provider/api_model_catalog_service.dart';

import '../../../support/in_memory_filesystem.dart';

void main() {
  test('Claude live API ids take precedence for an API-key provider', () async {
    final service = ApiModelCatalogService(
      protocol: ApiModelCatalogProtocol.anthropic,
      cacheDirectory: 'claude_models',
      fs: InMemoryFilesystem(),
      basePath: '/data/tp',
      httpClient: MockClient(
        (_) async => http.Response(
          '{"data":[{"id":"live-claude-model"}]}',
          200,
        ),
      ),
    );
    const provider = AppProviderConfig(
      id: 'anthropic-api',
      cli: CliTool.claude,
      name: 'Anthropic API',
      apiKey: 'secret',
    );
    await service.ensureLoaded(providerId: provider.id, provider: provider);

    final capability = ClaudeProviderCapability(modelsService: service);
    final models = capability.modelCandidates(
      provider: provider,
      providerId: provider.id,
      currentModel: '',
    );

    expect(models, contains('live-claude-model'));
    expect(models, isNot(contains('claude-sonnet-4-6')));
  });

  test('Claude OAuth provider uses aliases and static ids', () {
    const provider = AppProviderConfig(
      id: 'claude-official',
      cli: CliTool.claude,
      name: 'Claude Official',
      category: AppProviderCategory.official,
      isOfficial: true,
      config: {'env': {}},
    );
    final capability = ClaudeProviderCapability();
    final models = capability.modelCandidates(
      provider: provider,
      providerId: provider.id,
      currentModel: '',
    );

    expect(models, contains('sonnet'));
    expect(models, contains('claude-sonnet-5'));
    expect(models, contains('claude-opus-4-8'));
  });

  test('Claude capability is refreshable', () {
    expect(ClaudeProviderCapability(), isA<RefreshableProviderModelCapability>());
  });
}
