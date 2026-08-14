import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/services/cli/opencode/provider/opencode_model_catalog.dart';
import 'package:teampilot/services/cli/opencode/provider/opencode_models_service.dart';
import 'package:teampilot/services/cli/opencode/capabilities/provider.dart';
import 'package:teampilot/services/cli/registry/capabilities/provider_model_capability.dart';

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

  test('static fallback covers opencode-go and current zen ids', () {
    final go = OpencodeModelCatalog.knownModelsForProvider('opencode-go');
    expect(go, containsAll(['deepseek-v4-flash', 'qwen3.7-max', 'kimi-k3']));
    expect(go, hasLength(24));

    final zen = OpencodeModelCatalog.knownModelsForProvider('opencode');
    expect(zen, contains('claude-sonnet-5'));
    expect(zen, contains('gemini-3.6-flash'));
    expect(zen, hasLength(87));
  });
}
