import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/services/provider/api_model_catalog_service.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  test('parses model ids from API data, removes duplicates and blanks', () {
    final ids = ApiModelCatalogService.parseModelIds({
      'data': [
        {'id': ' model-b '},
        {'id': ''},
        {'id': 'model-a'},
        {'id': 'model-b'},
        {'name': 'missing-id'},
      ],
    });

    expect(ids, ['model-a', 'model-b']);
  });

  test('cache entry round trips only timestamp and model ids', () {
    const original = ApiModelCatalogCacheEntry(
      fetchedAtMs: 42,
      modelIds: ['model-a'],
    );

    expect(ApiModelCatalogCacheEntry.fromJson(original.toJson()).modelIds, [
      'model-a',
    ]);
    expect(original.toJson().keys, containsAll(['fetchedAtMs', 'modelIds']));
    expect(original.toJson().keys, isNot(contains('apiKey')));
  });

  test('OpenAI uses official v1 models endpoint and bearer auth', () async {
    late http.Request request;
    final service = ApiModelCatalogService(
      protocol: ApiModelCatalogProtocol.openAi,
      fs: InMemoryFilesystem(),
      basePath: '/data/tp',
      cacheDirectory: 'codex_models',
      httpClient: MockClient((next) async {
        request = next;
        return http.Response('{"data":[{"id":"gpt-test"}]}', 200);
      }),
    );

    await service.ensureLoaded(
      providerId: 'openai-test',
      provider: const AppProviderConfig(
        id: 'openai-test',
        cli: CliTool.codex,
        name: 'OpenAI',
        apiKey: 'secret',
      ),
    );

    expect(request.url.toString(), 'https://api.openai.com/v1/models');
    expect(request.headers['authorization'], 'Bearer secret');
    expect(request.headers.containsKey('x-api-key'), isFalse);
    expect(service.modelIdsFor(providerId: 'openai-test'), ['gpt-test']);
  });

  test('Anthropic appends v1 models to a custom API root', () async {
    late http.Request request;
    final service = ApiModelCatalogService(
      protocol: ApiModelCatalogProtocol.anthropic,
      fs: InMemoryFilesystem(),
      basePath: '/data/tp',
      cacheDirectory: 'claude_models',
      httpClient: MockClient((next) async {
        request = next;
        return http.Response('{"data":[{"id":"claude-test"}]}', 200);
      }),
    );

    await service.ensureLoaded(
      providerId: 'anthropic-test',
      provider: const AppProviderConfig(
        id: 'anthropic-test',
        cli: CliTool.claude,
        name: 'Anthropic',
        apiKey: 'secret',
        baseUrl: 'https://proxy.example.test/anthropic',
      ),
    );

    expect(
      request.url.toString(),
      'https://proxy.example.test/anthropic/v1/models',
    );
    expect(request.headers['x-api-key'], 'secret');
    expect(request.headers['anthropic-version'], '2023-06-01');
  });

  test('successful refresh writes cache and notifies listeners', () async {
    final fs = InMemoryFilesystem();
    var notifications = 0;
    final service = ApiModelCatalogService(
      protocol: ApiModelCatalogProtocol.openAi,
      fs: fs,
      basePath: '/data/tp',
      cacheDirectory: 'codex_models',
      httpClient: MockClient(
        (_) async => http.Response('{"data":[{"id":"gpt-test"}]}', 200),
      ),
    );
    service.catalogUpdates.addListener(() => notifications++);

    await service.ensureLoaded(
      providerId: 'openai-test',
      provider: const AppProviderConfig(
        id: 'openai-test',
        cli: CliTool.codex,
        name: 'OpenAI',
        apiKey: 'secret',
      ),
    );

    expect(notifications, 1);
    expect(
      fs.files.keys,
      contains('/data/tp/cache/codex_models/openai-test.json'),
    );
  });

  test('fresh disk cache avoids a network request', () async {
    final fs = InMemoryFilesystem();
    final writer = ApiModelCatalogService(
      protocol: ApiModelCatalogProtocol.openAi,
      fs: fs,
      basePath: '/data/tp',
      cacheDirectory: 'codex_models',
      httpClient: MockClient((_) async => http.Response('', 500)),
    );
    await writer.writeCacheForTest(
      providerId: 'openai-test',
      entry: ApiModelCatalogCacheEntry(
        fetchedAtMs: DateTime.now().millisecondsSinceEpoch,
        modelIds: const ['cached-model'],
      ),
    );

    var requests = 0;
    final reader = ApiModelCatalogService(
      protocol: ApiModelCatalogProtocol.openAi,
      fs: fs,
      basePath: '/data/tp',
      cacheDirectory: 'codex_models',
      httpClient: MockClient((_) async {
        requests++;
        return http.Response('', 500);
      }),
    );
    await reader.ensureLoaded(
      providerId: 'openai-test',
      provider: const AppProviderConfig(
        id: 'openai-test',
        cli: CliTool.codex,
        name: 'OpenAI',
        apiKey: 'secret',
      ),
    );

    expect(requests, 0);
    expect(reader.modelIdsFor(providerId: 'openai-test'), ['cached-model']);
  });

  test('expired cache is replaced by a successful live response', () async {
    final fs = InMemoryFilesystem();
    final service = ApiModelCatalogService(
      protocol: ApiModelCatalogProtocol.openAi,
      fs: fs,
      basePath: '/data/tp',
      cacheDirectory: 'codex_models',
      httpClient: MockClient(
        (_) async => http.Response('{"data":[{"id":"live-model"}]}', 200),
      ),
      cacheTtl: const Duration(minutes: 1),
    );
    await service.writeCacheForTest(
      providerId: 'openai-test',
      entry: ApiModelCatalogCacheEntry(
        fetchedAtMs: DateTime.now()
            .subtract(const Duration(hours: 1))
            .millisecondsSinceEpoch,
        modelIds: const ['old-model'],
      ),
    );

    await service.ensureLoaded(
      providerId: 'openai-test',
      provider: const AppProviderConfig(
        id: 'openai-test',
        cli: CliTool.codex,
        name: 'OpenAI',
        apiKey: 'secret',
      ),
    );

    expect(service.modelIdsFor(providerId: 'openai-test'), ['live-model']);
  });

  test(
    'failed live refresh keeps a valid disk cache and does not throw',
    () async {
      final fs = InMemoryFilesystem();
      final service = ApiModelCatalogService(
        protocol: ApiModelCatalogProtocol.openAi,
        fs: fs,
        basePath: '/data/tp',
        cacheDirectory: 'codex_models',
        httpClient: MockClient((_) async => http.Response('not-json', 500)),
        cacheTtl: const Duration(minutes: 1),
      );
      await service.writeCacheForTest(
        providerId: 'openai-test',
        entry: ApiModelCatalogCacheEntry(
          fetchedAtMs: DateTime.now()
              .subtract(const Duration(hours: 1))
              .millisecondsSinceEpoch,
          modelIds: const ['cached-model'],
        ),
      );

      await expectLater(
        service.ensureLoaded(
          providerId: 'openai-test',
          provider: const AppProviderConfig(
            id: 'openai-test',
            cli: CliTool.codex,
            name: 'OpenAI',
            apiKey: 'secret',
          ),
        ),
        completes,
      );
      expect(service.modelIdsFor(providerId: 'openai-test'), ['cached-model']);
    },
  );

  test('missing API key skips network and leaves no live ids', () async {
    var requests = 0;
    final service = ApiModelCatalogService(
      protocol: ApiModelCatalogProtocol.openAi,
      fs: InMemoryFilesystem(),
      basePath: '/data/tp',
      cacheDirectory: 'codex_models',
      httpClient: MockClient((_) async {
        requests++;
        return http.Response('{"data":[{"id":"unexpected"}]}', 200);
      }),
    );

    await service.ensureLoaded(
      providerId: 'oauth-provider',
      provider: const AppProviderConfig(
        id: 'oauth-provider',
        cli: CliTool.codex,
        name: 'OAuth',
      ),
    );

    expect(requests, 0);
    expect(service.modelIdsFor(providerId: 'oauth-provider'), isEmpty);
  });
}
