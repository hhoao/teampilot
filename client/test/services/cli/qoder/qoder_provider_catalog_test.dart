import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/cli/qoder/capabilities/provider.dart';
import 'package:teampilot/services/cli/qoder/provider/qoder_auth_store.dart';
import 'package:teampilot/services/cli/qoder/provider/qoder_models_service.dart';
import 'package:teampilot/services/cli/registry/capabilities/provider_capability.dart';

import '../../../support/in_memory_filesystem.dart';

void main() {
  test('catalog uses the live account models when available', () async {
    final fs = InMemoryFilesystem();
    final store = QoderAuthStore(
      fs: fs,
      basePath: '/app',
      pathContext: p.posix,
      machineHome: '/home/me',
    );
    final dir = store.providerAuthDir('work');
    await fs.ensureDir(dir);
    await fs.writeString(p.join(dir, QoderAuthStore.userFileName), 'USER');
    await fs.writeString(
      p.join(dir, QoderAuthStore.machineIdFileName),
      'MACHINE',
    );
    final service = QoderModelsService(
      fs: fs,
      basePath: '/app',
      machineHome: '/home/me',
      opener: ({required executable, required configDir, required timeout}) async {
        return const QoderModelsSnapshot(
          modelIds: ['auto', 'qwen3.8-max', 'smodel'],
          defaultModelId: 'auto',
          names: {
            'auto': 'Auto (default)',
            'qwen3.8-max': 'Qwen3.8-Max',
            'smodel': 'Sonus',
          },
        );
      },
    );
    await service.ensureLoaded(providerId: 'work');

    final capability = QoderProviderCapability(modelsService: service);
    final models = capability.catalogSources.single.modelsFor(
      provider: null,
      providerId: 'work',
    );

    expect(models, ['auto', 'qwen3.8-max', 'smodel']);
    expect(
      providerModelLabel(
        capability,
        providerId: 'work',
        modelId: 'qwen3.8-max',
      ),
      'Qwen3.8-Max',
    );
    expect(
      providerModelDescription(
        capability,
        providerId: 'unconfigured',
        modelId: 'smodel',
      ),
      'Reasoning · Vision · New · 8.00x Credit',
    );
  });

  test('catalog falls back to the full static list without a probe', () {
    const capability = QoderProviderCapability();
    final models = capability.catalogSources.single.modelsFor(
      provider: null,
      providerId: 'unconfigured',
    );

    expect(models, contains('auto'));
    expect(models, contains('smodel'));
    expect(models, contains('cmodel'));
    expect(models, contains('mmodel'));
    expect(
      providerModelLabel(
        capability,
        providerId: 'unconfigured',
        modelId: 'smodel',
      ),
      'Sonus',
    );
  });
}
