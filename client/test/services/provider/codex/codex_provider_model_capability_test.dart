import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/services/cli/codex/capabilities/provider.dart';
import 'package:teampilot/services/cli/registry/capabilities/provider_capability.dart';
import 'package:teampilot/services/provider/api_model_catalog_service.dart';

import '../../../support/in_memory_filesystem.dart';

void main() {
  test('Codex live API ids take precedence for an API-key provider', () async {
    final service = ApiModelCatalogService(
      protocol: ApiModelCatalogProtocol.openAi,
      cacheDirectory: 'codex_models',
      fs: InMemoryFilesystem(),
      basePath: '/data/tp',
      httpClient: MockClient(
        (_) async => http.Response(
          '{"data":[{"id":"live-codex-model"}]}',
          200,
        ),
      ),
    );
    const provider = AppProviderConfig(
      id: 'openai-api',
      cli: CliTool.codex,
      name: 'OpenAI API',
      apiKey: 'secret',
    );
    await service.ensureLoaded(providerId: provider.id, provider: provider);

    final capability = CodexProviderCapability(modelsService: service);
    final models = capability.modelCandidates(
      provider: provider,
      providerId: provider.id,
      currentModel: '',
    );

    expect(models, contains('live-codex-model'));
    expect(models, isNot(contains('gpt-5.3-codex')));
  });

  test('Codex OAuth provider uses static catalog without a network request', () async {
    var requests = 0;
    final service = ApiModelCatalogService(
      protocol: ApiModelCatalogProtocol.openAi,
      cacheDirectory: 'codex_models',
      fs: InMemoryFilesystem(),
      basePath: '/data/tp',
      httpClient: MockClient((_) async {
        requests++;
        return http.Response('{}', 200);
      }),
    );
    const provider = AppProviderConfig(
      id: 'openai-official',
      cli: CliTool.codex,
      name: 'OpenAI Official',
      category: AppProviderCategory.official,
      isOfficial: true,
    );
    final capability = CodexProviderCapability(modelsService: service);

    await capability.refreshModelCatalog(
      providerId: provider.id,
      provider: provider,
    );

    expect(
      capability.modelCandidates(
        provider: provider,
        providerId: provider.id,
        currentModel: '',
      ),
      contains('gpt-5.3-codex'),
    );
    expect(requests, 0);
  });

  test('Codex capability is refreshable', () {
    expect(CodexProviderCapability(), isA<RefreshableProviderModelCapability>());
  });
}
