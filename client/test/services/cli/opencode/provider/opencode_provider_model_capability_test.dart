import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/services/cli/opencode/provider/opencode_models_service.dart';
import 'package:teampilot/services/cli/opencode/provider/opencode_provider_model_capability.dart';
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
    final capability = OpencodeProviderModelCapability(modelsService: service);
    final models = capability.modelCandidates(
      provider: null,
      providerId: 'opencode',
      currentModel: '',
    );
    expect(models, containsAll(['live-model-a', 'live-model-b']));
  });

  test('falls back to static catalog without service', () {
    final capability = OpencodeProviderModelCapability();
    final models = capability.modelCandidates(
      provider: null,
      providerId: 'opencode',
      currentModel: '',
    );
    expect(models, contains('big-pickle'));
  });

  test('is refreshable and exposes picker mode', () {
    final capability = OpencodeProviderModelCapability();
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
}
