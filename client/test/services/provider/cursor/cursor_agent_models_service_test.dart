import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/cursor/provider/cursor_agent_models_service.dart';

import '../../../support/in_memory_filesystem.dart';

void main() {
  test('reads fresh disk cache without invoking process', () async {
    final fs = InMemoryFilesystem();
    final service = CursorAgentModelsService(
      fs: fs,
      basePath: '/data/tp',
      processRunner: (_, _, {environment, workingDirectory}) async {
        throw StateError('process should not run');
      },
      storage: fakeHomeStorage(filesystem: fs),
    );

    final entry = CursorAgentModelsCacheEntry(
      fetchedAtMs: DateTime.now().millisecondsSinceEpoch,
      modelIds: const ['gpt-5.2'],
      defaultModelId: 'gpt-5.2',
    );
    await service.writeCacheForTest(providerId: '', entry: entry);

    await service.ensureLoaded(providerId: '');
    expect(service.modelIdsFor(), ['gpt-5.2']);
    expect(service.defaultModelIdFor(), 'gpt-5.2');
  });

  test('a cold probe completes and caches the parsed ids', () async {
    final fs = InMemoryFilesystem();
    var calls = 0;
    final service = CursorAgentModelsService(
      fs: fs,
      basePath: '/data/tp',
      storage: fakeHomeStorage(filesystem: fs),
      processRunner: (_, _, {environment, workingDirectory}) async {
        calls++;
        return const CursorAgentModelsProcessResult(
          exitCode: 0,
          stdout:
              'Available models\n'
              'gpt-5.2 - GPT-5.2\n'
              'sonnet-4.6 - Sonnet 4.6\n'
              'Tip: use --model to switch\n',
          stderr: '',
        );
      },
    );

    await service
        .ensureLoaded(providerId: 'cursor-account')
        .timeout(const Duration(seconds: 2));

    expect(calls, 1);
    expect(service.modelIdsFor(providerId: 'cursor-account'), [
      'gpt-5.2',
      'sonnet-4.6',
    ]);
  });
}
