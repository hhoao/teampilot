import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:teampilot/services/cli/opencode/provider/opencode_models_service.dart';

import '../../../support/in_memory_filesystem.dart';

const _modelsDevUrl = 'https://models.dev/api.json';
const _zenModelsUrl = 'https://opencode.ai/zen/v1/models';
const _goModelsUrl = 'https://opencode.ai/zen/go/v1/models';

const _apiJson = '''
{
  "opencode": {"name": "OpenCode Zen", "models": {"claude-sonnet-4-5": {}, "deepseek-v4-flash-free": {}}},
  "opencode-go": {"name": "OpenCode Go", "models": {"deepseek-v4-flash": {}, "qwen3.6-plus": {}}},
  "openai": {"name": "OpenAI", "models": {"gpt-4o": {}}},
  "empty-provider": {"name": "X", "models": {}}
}
''';

/// Served catalogs: the Zen endpoint no longer lists `deepseek-v4-flash-free`,
/// which models.dev still advertises.
const _zenServedJson = '''
{"object": "list", "data": [{"id": "claude-sonnet-4-5"}, {"id": "deepseek-v4.1-flash-free"}]}
''';

const _goServedJson = '''
{"object": "list", "data": [{"id": "deepseek-v4.1-flash"}, {"id": "hy4-preview"}]}
''';

http.Client _client({
  void Function(String url)? onRequest,
  bool servedEndpointsFail = false,
}) {
  return MockClient((request) async {
    final url = request.url.toString();
    onRequest?.call(url);
    if (url == _modelsDevUrl) return http.Response(_apiJson, 200);
    if (servedEndpointsFail) return http.Response('boom', 503);
    if (url == _zenModelsUrl) return http.Response(_zenServedJson, 200);
    if (url == _goModelsUrl) return http.Response(_goServedJson, 200);
    return http.Response('not found', 404);
  });
}

OpencodeModelsCacheEntry _entry(Map<String, List<String>> byProvider) =>
    OpencodeModelsCacheEntry(
      fetchedAtMs: DateTime.now().millisecondsSinceEpoch,
      modelsByProvider: byProvider,
    );

void main() {
  test('served catalogs override the retired ids models.dev keeps', () async {
    final fs = InMemoryFilesystem();
    final service = OpencodeModelsService(
      fs: fs,
      basePath: '/data/tp',
      httpClient: _client(),
      storage: fakeHomeStorage(filesystem: fs),
    );

    await service.ensureLoaded();

    expect(
      service.modelIdsFor(providerId: 'opencode'),
      ['claude-sonnet-4-5', 'deepseek-v4.1-flash-free'],
    );
    expect(
      service.modelIdsFor(providerId: 'opencode'),
      isNot(contains('deepseek-v4-flash-free')),
      reason: 'models.dev lists it, the Zen endpoint no longer serves it',
    );
    expect(service.modelIdsFor(providerId: 'opencode-go'), [
      'deepseek-v4.1-flash',
      'hy4-preview',
    ]);
    // Other providers keep the models.dev slice (no served endpoint to ask).
    expect(service.modelIdsFor(providerId: 'openai'), ['gpt-4o']);
    expect(service.modelIdsFor(providerId: 'unknown'), isEmpty);
  });

  test('keeps the models.dev slice when a served endpoint fails', () async {
    final fs = InMemoryFilesystem();
    final service = OpencodeModelsService(
      fs: fs,
      basePath: '/data/tp',
      httpClient: _client(servedEndpointsFail: true),
      storage: fakeHomeStorage(filesystem: fs),
    );

    await service.ensureLoaded();

    expect(
      service.modelIdsFor(providerId: 'opencode'),
      ['claude-sonnet-4-5', 'deepseek-v4-flash-free'],
    );
    expect(service.modelIdsFor(providerId: 'openai'), ['gpt-4o']);
  });

  test('reads fresh disk cache without HTTP', () async {
    final fs = InMemoryFilesystem();
    final neverCalled = MockClient((request) async {
      throw StateError('http should not be called');
    });
    // seed disk cache, then use a fresh service (empty memory)
    await OpencodeModelsService(
      fs: fs,
      basePath: '/data/tp',
      httpClient: neverCalled,
      storage: fakeHomeStorage(filesystem: fs),
    ).writeCacheForTest(
      _entry({
        'opencode': const ['gpt-5.2'],
      }),
    );

    final service = OpencodeModelsService(
      fs: fs,
      basePath: '/data/tp',
      httpClient: neverCalled,
      storage: fakeHomeStorage(filesystem: fs),
    );
    await service.ensureLoaded();
    expect(service.modelIdsFor(providerId: 'opencode'), ['gpt-5.2']);
  });

  test('falls back to stale disk cache when fetch fails', () async {
    final fs = InMemoryFilesystem();
    final stale = OpencodeModelsCacheEntry(
      fetchedAtMs: 0,
      modelsByProvider: {
        'opencode': const ['claude-haiku-4-5'],
      },
    );
    final service = OpencodeModelsService(
      fs: fs,
      basePath: '/data/tp',
      httpClient: MockClient((request) async => http.Response('oops', 500)),
      storage: fakeHomeStorage(filesystem: fs),
    );
    await service.writeCacheForTest(stale);

    await service.ensureLoaded();
    expect(service.modelIdsFor(providerId: 'opencode'), ['claude-haiku-4-5']);
  });

  test('returns empty without crashing on network error', () async {
    final fs = InMemoryFilesystem();
    final service = OpencodeModelsService(
      fs: fs,
      basePath: '/data/tp',
      httpClient: MockClient(
        (request) async => throw Exception('network down'),
      ),
      storage: fakeHomeStorage(filesystem: fs),
    );
    await service.ensureLoaded();
    expect(service.modelIdsFor(providerId: 'opencode'), isEmpty);
  });

  test('dedupes concurrent ensureLoaded calls', () async {
    var modelsDevCalls = 0;
    final fs = InMemoryFilesystem();
    final service = OpencodeModelsService(
      fs: fs,
      basePath: '/data/tp',
      httpClient: _client(
        onRequest: (url) {
          if (url == _modelsDevUrl) modelsDevCalls++;
        },
      ),
      storage: fakeHomeStorage(filesystem: fs),
    );
    final f1 = service.ensureLoaded();
    final f2 = service.ensureLoaded();
    await Future.wait([f1, f2]);
    expect(modelsDevCalls, 1);
  });
}
