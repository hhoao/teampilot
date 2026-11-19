import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/codebuddy/provider/codebuddy_auth_store.dart';
import 'package:teampilot/services/cli/codebuddy/provider/codebuddy_models_service.dart';

import '../../../support/in_memory_filesystem.dart';

void main() {
  late InMemoryFilesystem fs;

  String machineAuthDir(String home) => CodebuddyAuthStore(
    fs: fs,
    basePath: '/app',
    pathContext: fs.pathContext,
  ).authDirIn(home);

  Future<void> writeProviderToken(String providerId, String token) async {
    await fs.ensureDir('/app/providers/codebuddy');
    await fs.atomicWrite(
      '/app/providers/codebuddy/$providerId.auth.json',
      jsonEncode({
        'accessToken': token,
        'expiresAt': DateTime.now()
            .add(const Duration(days: 1))
            .millisecondsSinceEpoch,
      }),
    );
  }

  setUp(() {
    fs = InMemoryFilesystem();
  });

  test(
    'probes the account catalog, caches it and notifies listeners',
    () async {
      await writeProviderToken('work', 'tok-1');
      var calls = 0;
      var notified = 0;
      final service = CodebuddyModelsService(
        fs: fs,
        basePath: '/app',
        machineHome: '/home/me',
        opener:
            ({
              required executable,
              required configDir,
              required environment,
              required timeout,
            }) async {
              calls++;
              expect(executable, 'codebuddy');
              expect(environment['CODEBUDDY_AUTH_TOKEN'], 'tok-1');
              expect(configDir, '/app/tmp/codebuddy-models/work');
              return const CodebuddyModelsSnapshot(
                modelIds: ['hy3', 'glm-5.3'],
                defaultModelId: 'hy3',
                names: {'hy3': 'Hy3', 'glm-5.3': 'GLM-5.3'},
                descriptions: {
                  'hy3': 'x0.00 credits',
                  'glm-5.3': 'x0.69 credits',
                },
                effortOptions: {
                  'hy3': ['low', 'medium', 'high', 'xhigh'],
                  'glm-5.3': ['low', 'high', 'max'],
                },
              );
            },
      );
      service.catalogUpdates.addListener(() => notified++);

      await service.ensureLoaded(providerId: 'work');

      expect(service.modelIdsFor(providerId: 'work'), ['hy3', 'glm-5.3']);
      expect(service.defaultModelIdFor(providerId: 'work'), 'hy3');
      expect(
        service.modelNameFor(providerId: 'work', modelId: 'glm-5.3'),
        'GLM-5.3',
      );
      expect(
        service.modelDescriptionFor(providerId: 'work', modelId: 'glm-5.3'),
        'x0.69 credits',
      );
      expect(service.effortOptionsFor(providerId: 'work', modelId: 'hy3'), [
        'low',
        'medium',
        'high',
        'xhigh',
      ]);
      expect(service.liveEffortOptions('glm-5.3'), ['low', 'high', 'max']);
      expect(calls, 1);
      expect(notified, 1);

      await service.ensureLoaded(providerId: 'work');
      expect(calls, 1, reason: 'fresh memory cache is reused');

      await service.ensureLoaded(providerId: 'work', forceRefresh: true);
      expect(calls, 2);
    },
  );

  test('persists the catalog and reuses it from a new instance', () async {
    await writeProviderToken('work', 'tok-1');
    var firstCalls = 0;
    final first = CodebuddyModelsService(
      fs: fs,
      basePath: '/app',
      machineHome: '/home/me',
      opener:
          ({
            required executable,
            required configDir,
            required environment,
            required timeout,
          }) async {
            firstCalls++;
            return const CodebuddyModelsSnapshot(
              modelIds: ['hy3', 'hy4free'],
              descriptions: {'hy4free': 'x0.00 credits'},
              effortOptions: {
                'hy3': ['low', 'high'],
                'hy4free': ['high'],
              },
            );
          },
    );
    await first.ensureLoaded(providerId: 'work');
    expect(firstCalls, 1);

    var secondCalls = 0;
    final second = CodebuddyModelsService(
      fs: fs,
      basePath: '/app',
      machineHome: '/home/me',
      opener:
          ({
            required executable,
            required configDir,
            required environment,
            required timeout,
          }) async {
            secondCalls++;
            return const CodebuddyModelsSnapshot(modelIds: ['other']);
          },
    );
    await second.ensureLoaded(providerId: 'work');

    expect(secondCalls, 0, reason: 'fresh disk cache skips the probe');
    expect(second.modelIdsFor(providerId: 'work'), ['hy3', 'hy4free']);
    expect(second.liveEffortOptions('hy4free'), ['high']);
    expect(
      second.modelDescriptionFor(providerId: 'work', modelId: 'hy4free'),
      'x0.00 credits',
    );
  });

  test('does not probe without a provider or machine login', () async {
    var calls = 0;
    final service = CodebuddyModelsService(
      fs: fs,
      basePath: '/app',
      machineHome: '/home/me',
      opener:
          ({
            required executable,
            required configDir,
            required environment,
            required timeout,
          }) async {
            calls++;
            return const CodebuddyModelsSnapshot(modelIds: ['hy3']);
          },
    );

    await service.ensureLoaded(providerId: 'missing');

    expect(calls, 0);
    expect(service.modelIdsFor(providerId: 'missing'), isEmpty);
  });

  test('falls back to the machine login without a provider token', () async {
    final authDir = machineAuthDir('/home/me');
    await fs.ensureDir(authDir);
    await fs.writeString(
      fs.pathContext.join(authDir, 'Tencent-Cloud.info'),
      '{}',
    );

    var calls = 0;
    final service = CodebuddyModelsService(
      fs: fs,
      basePath: '/app',
      machineHome: '/home/me',
      opener:
          ({
            required executable,
            required configDir,
            required environment,
            required timeout,
          }) async {
            calls++;
            expect(environment, isEmpty);
            return const CodebuddyModelsSnapshot(modelIds: ['hy3']);
          },
    );

    await service.ensureLoaded(providerId: 'machine');

    expect(calls, 1);
    expect(service.modelIdsFor(providerId: 'machine'), ['hy3']);
  });
}
