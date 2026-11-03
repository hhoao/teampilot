import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/services/cli/opencode/provider/opencode_model_catalog.dart';
import 'package:teampilot/services/cli/opencode/provider/opencode_models_service.dart';
import 'package:teampilot/services/cli/opencode/capabilities/provider.dart';
import 'package:teampilot/services/cli/registry/capabilities/provider_capability.dart';

import '../../../../support/in_memory_filesystem.dart';

const _apiJson = '''
{"opencode": {"models": {"live-model-a": {}, "live-model-b": {}}}}
''';

void main() {
  test('uses live catalog when service loaded', () async {
    final fs = InMemoryFilesystem();
    final service = OpencodeModelsService(
      fs: fs,
      basePath: '/data/tp',
      httpClient: MockClient((request) async => http.Response(_apiJson, 200)),
      storage: fakeHomeStorage(filesystem: fs),
    );
    await service.ensureLoaded();

    // service is a runtime value, so the capability cannot be const here.
    final capability = OpencodeProviderCapability(modelsService: service);
    final models = capability.modelCandidates(
      provider: null,
      providerId: 'opencode',
      currentModel: '',
    );
    expect(models, containsAll(['live-model-a', 'live-model-b']));
  });

  test('falls back to static catalog without service', () {
    final capability = OpencodeProviderCapability();
    final models = capability.modelCandidates(
      provider: null,
      providerId: 'opencode',
      currentModel: '',
    );
    expect(models, contains('big-pickle'));
  });

  test('is refreshable and exposes picker mode', () {
    final capability = OpencodeProviderCapability();
    expect(capability, isA<RefreshableProviderModelCapability>());
    expect(
      capability.pickerMode(
        const AppProviderConfig(
          id: 'opencode',
          cli: CliTool.opencode,
          name: 'OpenCode',
        ),
      ),
      ProviderModelPickerMode.catalogWithCustomEntry,
    );
  });

  test('the picker groups are labeled with the upstream namespace', () {
    final capability = OpencodeProviderCapability();
    final bound = AppProviderConfig(
      id: 'opencode',
      cli: CliTool.opencode,
      name: 'OpenCode',
      config: const {'opencodeSubscription': 'opencode-go'},
    );

    final groups = capability.modelGroups(provider: bound, currentModel: '');

    // The extra level shows the namespace itself — the same prefix written
    // into `model: "<namespace>/<model>"` — with no renamed labels in between.
    expect(groups.map((group) => group.namespace), ['opencode-go', 'opencode']);
    expect(groups.first.models, contains('hy4-preview'));
    expect(groups.last.models, contains('deepseek-v4.1-flash-free'));
    expect(groups.last.models, isNot(contains('hy4-preview')));
  });

  test('without a subscription the picker stays one flat level', () {
    final capability = OpencodeProviderCapability();
    const zen = AppProviderConfig(
      id: 'opencode',
      cli: CliTool.opencode,
      name: 'OpenCode',
    );
    expect(capability.modelGroups(provider: zen, currentModel: ''), isEmpty);
  });

  test('static fallback covers opencode-go and current zen ids', () {
    final go = OpencodeModelCatalog.knownModelsForProvider('opencode-go');
    expect(go, containsAll(['deepseek-v4.1-flash', 'kimi-k3', 'hy4-preview']));
    expect(go, hasLength(28));

    final zen = OpencodeModelCatalog.knownModelsForProvider('opencode');
    expect(zen, contains('claude-sonnet-5'));
    expect(zen, contains('gemini-3.6-flash'));
    expect(zen, hasLength(78));
  });

  test('deepseek-v4.1-flash-free is a Zen-only id, not a Go id', () {
    // Regression guard for the "opencode-go/<free model>" launch failure: the
    // Go subscription does not serve this model, so the static fallback must
    // not claim it does.
    final zen = OpencodeModelCatalog.knownModelsForProvider('opencode');
    final go = OpencodeModelCatalog.knownModelsForProvider('opencode-go');
    expect(zen, contains('deepseek-v4.1-flash-free'));
    expect(go, isNot(contains('deepseek-v4.1-flash-free')));
    expect(go, contains('deepseek-v4.1-flash'));
  });

  test('retired ids that models.dev still lists are not offered', () {
    // The reported failure: `opencode/deepseek-v4-flash-free` is in
    // models.dev but no longer served by the Zen endpoint, so picking it fails
    // upstream with "Model is unavailable".
    for (final providerId in const ['opencode', 'opencode-go']) {
      final ids = OpencodeModelCatalog.knownModelsForProvider(providerId);
      expect(ids, isNot(contains('deepseek-v4-flash-free')), reason: providerId);
    }
    expect(
      OpencodeModelCatalog.knownModelsForProvider('opencode'),
      contains('deepseek-v4.1-flash-free'),
    );
  });

  test('opencode-go keeps free models that it actually serves', () {
    // Free-ness alone is not a Go/Zen discriminator; several free ids are Go.
    final go = OpencodeModelCatalog.knownModelsForProvider('opencode-go');
    expect(
      go.where((id) => id.endsWith('-free')),
      isNotEmpty,
      reason: 'routing must key off catalog membership, not the -free suffix',
    );
  });
}
