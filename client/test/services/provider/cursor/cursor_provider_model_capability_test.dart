import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/services/cli/registry/capabilities/provider_model_capability.dart';
import 'package:teampilot/services/provider/cursor/cursor_agent_models_service.dart';
import 'package:teampilot/services/provider/cursor/cursor_provider_model_capability.dart';

import '../../../support/in_memory_filesystem.dart';

void main() {
  test('cursor capability exposes cached agent models', () async {
    final fs = InMemoryFilesystem();
    final models = CursorAgentModelsService(
      fs: fs,
      basePath: '/data/tp',
      processRunner: (_, _, {environment, workingDirectory}) async {
        throw StateError('process should not run');
      },
    );
    final capability = CursorProviderModelCapability(modelsService: models);

    const provider = AppProviderConfig(
      id: 'cursor-account',
      cli: CliTool.cursor,
      name: 'Cursor Account',
      category: AppProviderCategory.official,
      isOfficial: true,
    );

    expect(
      capability.pickerMode(provider),
      ProviderModelPickerMode.catalogWithCustomEntry,
    );
    expect(capability, isA<RefreshableProviderModelCapability>());

    await models.writeCacheForTest(
      providerId: 'cursor-account',
      entry: CursorAgentModelsCacheEntry(
        fetchedAtMs: DateTime.now().millisecondsSinceEpoch,
        modelIds: const ['gpt-5.2', 'composer-2.5-fast'],
        defaultModelId: 'composer-2.5-fast',
      ),
    );
    await models.ensureLoaded(providerId: 'cursor-account');

    expect(
      capability.modelCandidates(
        provider: provider,
        providerId: 'cursor-account',
        currentModel: '',
      ),
      ['composer-2.5-fast', 'gpt-5.2'],
    );
    expect(
      capability.defaultModel(provider: provider, providerId: 'cursor-account'),
      'composer-2.5-fast',
    );
  });
}
