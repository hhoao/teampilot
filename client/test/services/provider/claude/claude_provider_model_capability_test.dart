import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/services/cli/claude/capabilities/provider.dart';
import 'package:teampilot/services/cli/claude/provider/claude_provider_credentials_service.dart';
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
        (_) async =>
            http.Response('{"data":[{"id":"live-claude-model"}]}', 200),
      ),
      storage: fakeHomeStorage(),
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

  test('Claude OAuth rows prefer the live cache once fetched', () async {
    final service = ApiModelCatalogService(
      protocol: ApiModelCatalogProtocol.anthropic,
      cacheDirectory: 'claude_models',
      fs: InMemoryFilesystem(),
      basePath: '/data/tp',
      httpClient: MockClient((_) async => http.Response('{}', 200)),
      storage: fakeHomeStorage(),
    );
    const provider = AppProviderConfig(
      id: 'claude-official',
      cli: CliTool.claude,
      name: 'Claude Official',
      category: AppProviderCategory.official,
      isOfficial: true,
      config: {'env': {}},
    );
    await service.writeCacheForTest(
      providerId: provider.id,
      entry: ApiModelCatalogCacheEntry(
        fetchedAtMs: DateTime.now().millisecondsSinceEpoch,
        modelIds: ['claude-opus-5-5'],
      ),
    );

    final capability = ClaudeProviderCapability(modelsService: service);

    expect(
      capability.modelCandidates(
        provider: provider,
        providerId: provider.id,
        currentModel: '',
      ),
      ['claude-opus-5-5'],
    );
  });

  test('refresh sends the OAuth token to the Anthropic models API', () async {
    final fs = InMemoryFilesystem();
    await fs.ensureDir('/home/me/.claude');
    await fs.atomicWrite(
      '/home/me/.claude/.credentials.json',
      jsonEncode({
        'claudeAiOauth': {
          'accessToken': 'oauth-token',
          'expiresAt': DateTime.now()
              .add(const Duration(hours: 1))
              .millisecondsSinceEpoch,
        },
      }),
    );
    final credentials = ClaudeProviderCredentialsService(
      storage: fakeHomeStorage(),
      fs: fs,
      basePath: '/data/tp',
      resolveHomeDirectory: () => '/home/me',
    );
    late http.Request request;
    final service = ApiModelCatalogService(
      protocol: ApiModelCatalogProtocol.anthropic,
      cacheDirectory: 'claude_models',
      fs: InMemoryFilesystem(),
      basePath: '/data/tp',
      httpClient: MockClient((next) async {
        request = next;
        return http.Response('{"data":[{"id":"claude-opus-5-5"}]}', 200);
      }),
      storage: fakeHomeStorage(),
    );
    const provider = AppProviderConfig(
      id: 'claude-official',
      cli: CliTool.claude,
      name: 'Claude Official',
      category: AppProviderCategory.official,
      isOfficial: true,
      config: {'env': {}},
    );
    final capability = ClaudeProviderCapability(
      modelsService: service,
      credentials: credentials,
    );

    await capability.refreshModelCatalog(
      providerId: provider.id,
      provider: provider,
    );

    expect(request.headers['authorization'], 'Bearer oauth-token');
    expect(request.headers['anthropic-beta'], 'oauth-2025-04-20');
    expect(service.modelIdsFor(providerId: provider.id), ['claude-opus-5-5']);
  });

  test('Claude capability is refreshable', () {
    expect(
      ClaudeProviderCapability(),
      isA<RefreshableProviderModelCapability>(),
    );
  });
}
