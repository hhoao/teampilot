import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/provider/cursor/cursor_agent_models_service.dart';

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
}
