import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/cli/qoder/provider/qoder_auth_store.dart';
import 'package:teampilot/services/cli/qoder/provider/qoder_models_service.dart';

import '../../../support/in_memory_filesystem.dart';

void main() {
  late InMemoryFilesystem fs;
  late QoderAuthStore authStore;

  setUp(() async {
    fs = InMemoryFilesystem();
    authStore = QoderAuthStore(
      fs: fs,
      basePath: '/app',
      pathContext: p.posix,
      machineHome: '/home/me',
    );
    final dir = authStore.providerAuthDir('work');
    await fs.ensureDir(dir);
    await fs.writeString(p.join(dir, QoderAuthStore.userFileName), 'USER');
    await fs.writeString(
      p.join(dir, QoderAuthStore.machineIdFileName),
      'MACHINE',
    );
  });

  test('fetches, caches and exposes the account models', () async {
    var calls = 0;
    var notified = 0;
    final service = QoderModelsService(
      fs: fs,
      basePath: '/app',
      machineHome: '/home/me',
      opener: ({required executable, required configDir, required timeout}) async {
        calls++;
        // ignore: avoid_print
        expect(executable, 'qodercli');
        expect(
          await fs.readString(p.join(configDir, '.auth', 'user')),
          'USER',
          reason: 'probe config dir is seeded from the provider auth',
        );
        // ignore: avoid_print
        return const QoderModelsSnapshot(
          modelIds: ['auto', 'qwen3.8-max'],
          defaultModelId: 'auto',
        );
      },
    );
    service.catalogUpdates.addListener(() => notified++);

    await service.ensureLoaded(providerId: 'work');

    expect(service.modelIdsFor(providerId: 'work'), ['auto', 'qwen3.8-max']);
    expect(service.defaultModelIdFor(providerId: 'work'), 'auto');
    expect(calls, 1);
    expect(notified, 1);

    await service.ensureLoaded(providerId: 'work');
    expect(calls, 1, reason: 'fresh memory cache is reused');

    await service.ensureLoaded(providerId: 'work', forceRefresh: true);
    expect(calls, 2);
  });

  test('persists the catalog to disk and reuses it in a new instance', () async {
    var firstCalls = 0;
    final first = QoderModelsService(
      fs: fs,
      basePath: '/app',
      machineHome: '/home/me',
      opener: ({required executable, required configDir, required timeout}) async {
        firstCalls++;
        return const QoderModelsSnapshot(
          modelIds: ['auto', 'glm-5.3'],
          defaultModelId: 'auto',
        );
      },
    );
    await first.ensureLoaded(providerId: 'work');
    expect(firstCalls, 1);

    var secondCalls = 0;
    final second = QoderModelsService(
      fs: fs,
      basePath: '/app',
      machineHome: '/home/me',
      opener: ({required executable, required configDir, required timeout}) async {
        secondCalls++;
        return const QoderModelsSnapshot(modelIds: ['other']);
      },
    );
    await second.ensureLoaded(providerId: 'work');

    expect(secondCalls, 0, reason: 'fresh disk cache skips the probe');
    expect(second.modelIdsFor(providerId: 'work'), ['auto', 'glm-5.3']);
  });

  test('does not probe without a provider or machine auth', () async {
    var calls = 0;
    final service = QoderModelsService(
      fs: fs,
      basePath: '/app',
      machineHome: '/home/me',
      opener: ({required executable, required configDir, required timeout}) async {
        calls++;
        return const QoderModelsSnapshot(modelIds: ['auto']);
      },
    );

    await service.ensureLoaded(providerId: 'missing');

    expect(calls, 0);
    expect(service.modelIdsFor(providerId: 'missing'), isEmpty);
  });

  test('falls back to the machine login when no provider auth exists', () async {
    await fs.ensureDir('/home/me/.qoder/.auth');
    await fs.writeString('/home/me/.qoder/.auth/user', 'MACHINE_USER');
    await fs.writeString('/home/me/.qoder/.auth/machine_id', 'MACHINE_ID');
    var calls = 0;
    final service = QoderModelsService(
      fs: fs,
      basePath: '/app',
      machineHome: '/home/me',
      opener: ({required executable, required configDir, required timeout}) async {
        calls++;
        expect(
          await fs.readString(p.join(configDir, '.auth', 'user')),
          'MACHINE_USER',
        );
        return const QoderModelsSnapshot(modelIds: ['auto', 'smodel']);
      },
    );

    await service.ensureLoaded(providerId: 'machine');

    expect(calls, 1);
    expect(service.modelIdsFor(providerId: 'machine'), ['auto', 'smodel']);
  });
}
