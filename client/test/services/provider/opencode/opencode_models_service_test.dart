import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:teampilot/services/cli/opencode/provider/opencode_models_service.dart';

import '../../../support/in_memory_filesystem.dart';

const _apiJson = '''
{
  "opencode": {"name": "OpenCode Zen", "models": {"claude-sonnet-4-5": {}, "gpt-5.2": {}}},
  "opencode-go": {"name": "OpenCode Go", "models": {"deepseek-v4-flash": {}, "qwen3.6-plus": {}}},
  "openai": {"name": "OpenAI", "models": {"gpt-4o": {}}},
  "empty-provider": {"name": "X", "models": {}}
}
''';

OpencodeModelsCacheEntry _entry(Map<String, List<String>> byProvider) =>
    OpencodeModelsCacheEntry(
      fetchedAtMs: DateTime.now().millisecondsSinceEpoch,
      modelsByProvider: byProvider,
    );

void main() {
  test('fetches live catalog and slices per provider', () async {
    final fs = InMemoryFilesystem();
    final service = OpencodeModelsService(
      fs: fs,
      basePath: '/data/tp',
      httpClient: MockClient((request) async {
        expect(request.url.toString(), 'https://models.dev/api.json');
        return http.Response(_apiJson, 200);
      }),
    );

    await service.ensureLoaded();
    expect(
      service.modelIdsFor(providerId: 'opencode'),
      contains('claude-sonnet-4-5'),
    );
    expect(
      service.modelIdsFor(providerId: 'opencode-go'),
      containsAll(['deepseek-v4-flash', 'qwen3.6-plus']),
    );
    expect(service.modelIdsFor(providerId: 'unknown'), isEmpty);
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
    ).writeCacheForTest(_entry({'opencode': const ['gpt-5.2']}));

    final service = OpencodeModelsService(
      fs: fs,
      basePath: '/data/tp',
      httpClient: neverCalled,
    );
    await service.ensureLoaded();
    expect(service.modelIdsFor(providerId: 'opencode'), ['gpt-5.2']);
  });

  test('falls back to stale disk cache when fetch fails', () async {
    final fs = InMemoryFilesystem();
    final stale = OpencodeModelsCacheEntry(
      fetchedAtMs: 0,
      modelsByProvider: {'opencode': const ['claude-haiku-4-5']},
    );
    final service = OpencodeModelsService(
      fs: fs,
      basePath: '/data/tp',
      httpClient: MockClient(
        (request) async => http.Response('oops', 500),
      ),
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
    );
    await service.ensureLoaded();
    expect(service.modelIdsFor(providerId: 'opencode'), isEmpty);
  });

  test('dedupes concurrent ensureLoaded calls', () async {
    var calls = 0;
    final fs = InMemoryFilesystem();
    final service = OpencodeModelsService(
      fs: fs,
      basePath: '/data/tp',
      httpClient: MockClient((request) async {
        calls++;
        return http.Response(_apiJson, 200);
      }),
    );
    final f1 = service.ensureLoaded();
    final f2 = service.ensureLoaded();
    await Future.wait([f1, f2]);
    expect(calls, 1);
  });
}
