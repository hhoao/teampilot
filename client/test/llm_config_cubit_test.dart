import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:teampilot/cubits/llm_config_cubit.dart';
import 'package:teampilot/models/llm_config.dart';
import 'package:teampilot/repositories/app_settings_repository.dart';
import 'package:teampilot/repositories/llm_config_store.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/provider/llm_config_path_resolver.dart';
import 'package:teampilot/services/storage/runtime_storage_context.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = await Directory.systemTemp.createTemp('llm_cubit_test_');
    final paths = AppPaths(tmp.path);
    RuntimeStorageContext.installForTesting(
      filesystem: LocalFilesystem(
        pathContext: AppPaths.pathContextForDataRoot(paths.basePath),
      ),
      paths: paths,
      home: '/home/test',
      cwd: tmp.path,
    );
  });

  tearDown(() async {
    RuntimeStorageContext.resetForTesting();
    AppPathsBootstrapper.resetForTesting();
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Future<File> writeConfig(String relativePath, Map<String, Object?> json) async {
    final file = File('${tmp.path}/$relativePath');
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(json));
    return file;
  }

  test('load uses CLI install dir as default when CLI is known', () async {
    final prefs = await SharedPreferences.getInstance();
    final cubit = LlmConfigCubit(
      appSettings: SharedPrefsAppSettingsRepository(prefs),
      executableResolver: () => '/opt/flashskyai/dist/flashskyai',
      storeFactory: (path) => LocalLlmConfigStore(path),
    );

    await cubit.load();

    expect(cubit.state.pathSource, LlmConfigPathSource.defaultPath);
    expect(cubit.state.configPathOverride, '');
    final ep = cubit.state.effectiveConfigPath.replaceAll(r'\', '/');
    expect(ep, endsWith('opt/flashskyai/llm/llm_config.json'));
  });

  test('load returns empty effective path when CLI is unknown', () async {
    final prefs = await SharedPreferences.getInstance();
    final cubit = LlmConfigCubit(
      appSettings: SharedPrefsAppSettingsRepository(prefs),
    );

    await cubit.load();

    expect(cubit.state.pathSource, LlmConfigPathSource.defaultPath);
    expect(cubit.state.effectiveConfigPath, '');
  });

  test('load uses override path when one is stored', () async {
    final file = await writeConfig('custom/llm.json', {
      'providers': {
        'foo': {'name': 'foo', 'apiKey': 'secret'}
      },
    });
    final prefs = await SharedPreferences.getInstance();
    await SharedPrefsAppSettingsRepository(prefs).saveLlmConfigPathOverride(file.path);

    final cubit = LlmConfigCubit(
      appSettings: SharedPrefsAppSettingsRepository(prefs),
    );
    await cubit.load();

    expect(cubit.state.pathSource, LlmConfigPathSource.userOverride);
    expect(
      p.normalize(cubit.state.effectiveConfigPath),
      p.normalize(file.path),
    );
    expect(cubit.state.config.providers.keys, contains('foo'));
  });

  test('setConfigPath persists, reloads, and reflects new providers', () async {
    final fileA = await writeConfig('a/llm.json', {
      'providers': {
        'a': {'name': 'a', 'apiKey': 'k'}
      }
    });
    final fileB = await writeConfig('b/llm.json', {
      'providers': {
        'b': {'name': 'b', 'apiKey': 'k'}
      }
    });

    final prefs = await SharedPreferences.getInstance();
    final cubit = LlmConfigCubit(
      appSettings: SharedPrefsAppSettingsRepository(prefs),
    );

    await cubit.setConfigPath(fileA.path);
    expect(cubit.state.config.providers.keys, ['a']);
    expect(cubit.state.pathSource, LlmConfigPathSource.userOverride);

    await cubit.setConfigPath(fileB.path);
    expect(cubit.state.config.providers.keys, ['b']);
    expect(
      p.normalize(cubit.state.effectiveConfigPath),
      p.normalize(fileB.path),
    );

    // verify it persisted
    final reloaded = SharedPrefsAppSettingsRepository(prefs);
    expect(await reloaded.loadLlmConfigPathOverride(), fileB.path);
  });

  test('setConfigPath(null) reverts to default path', () async {
    final prefs = await SharedPreferences.getInstance();
    await SharedPrefsAppSettingsRepository(prefs).saveLlmConfigPathOverride('/some/path');

    final cubit = LlmConfigCubit(
      appSettings: SharedPrefsAppSettingsRepository(prefs),
    );
    await cubit.setConfigPath(null);

    expect(cubit.state.pathSource, LlmConfigPathSource.defaultPath);
    expect(cubit.state.configPathOverride, '');
    expect(await SharedPrefsAppSettingsRepository(prefs).loadLlmConfigPathOverride(), isNull);
  });

  test('renameProvider moves key and updates model references', () async {
    final prefs = await SharedPreferences.getInstance();
    final cubit = LlmConfigCubit(
      appSettings: SharedPrefsAppSettingsRepository(prefs),
      initialConfig: LlmConfig(
        providers: {
          'old-name': const LlmProviderConfig(
            name: 'old-name',
            type: 'api',
            providerType: 'openai',
          ),
        },
        models: {
          'm1': const LlmModelConfig(
            id: 'm1',
            name: 'gpt',
            provider: 'old-name',
            model: 'gpt-4',
            enabled: true,
          ),
        },
      ),
    );
    addTearDown(cubit.close);
    cubit.selectProvider('old-name');

    expect(cubit.renameProvider('old-name', 'new-name'), isTrue);
    await pumpEventQueue();

    expect(cubit.state.config.providers.containsKey('old-name'), isFalse);
    expect(cubit.state.config.providers['new-name']?.name, 'new-name');
    expect(cubit.state.config.models['m1']?.provider, 'new-name');
    expect(cubit.state.selectedProviderName, 'new-name');
  });

  test('renameProvider rejects duplicate name', () async {
    final prefs = await SharedPreferences.getInstance();
    final cubit = LlmConfigCubit(
      appSettings: SharedPrefsAppSettingsRepository(prefs),
      initialConfig: const LlmConfig(
        providers: {
          'a': LlmProviderConfig(name: 'a', type: 'api'),
          'b': LlmProviderConfig(name: 'b', type: 'api'),
        },
      ),
    );
    addTearDown(cubit.close);

    expect(cubit.renameProvider('a', 'b'), isFalse);
    expect(cubit.state.config.providers.containsKey('a'), isTrue);
  });

  test('load follows RuntimeStorageContext home for tilde override paths', () async {
    final homeA = await Directory.systemTemp.createTemp('llm_home_a_');
    final homeB = await Directory.systemTemp.createTemp('llm_home_b_');
    addTearDown(() async {
      if (await homeA.exists()) await homeA.delete(recursive: true);
      if (await homeB.exists()) await homeB.delete(recursive: true);
    });

    RuntimeStorageContext.installForTesting(
      filesystem: LocalFilesystem(
        pathContext: AppPaths.pathContextForDataRoot(homeA.path),
      ),
      paths: AppPaths(homeA.path),
      home: homeA.path,
      cwd: homeA.path,
    );

    final fileA = File(p.join(homeA.path, 'llm.json'));
    await fileA.writeAsString(jsonEncode({
      'providers': {
        'a': {'name': 'a', 'apiKey': 'k'},
      },
    }));

    final prefs = await SharedPreferences.getInstance();
    await SharedPrefsAppSettingsRepository(
      prefs,
    ).saveLlmConfigPathOverride('~/llm.json');

    final cubit = LlmConfigCubit(
      appSettings: SharedPrefsAppSettingsRepository(prefs),
    );
    addTearDown(cubit.close);

    await cubit.load();
    expect(
      p.normalize(cubit.state.effectiveConfigPath),
      p.normalize(fileA.path),
    );
    expect(cubit.state.config.providers.keys, ['a']);

    RuntimeStorageContext.installForTesting(
      filesystem: LocalFilesystem(
        pathContext: AppPaths.pathContextForDataRoot(homeB.path),
      ),
      paths: AppPaths(homeB.path),
      home: homeB.path,
      cwd: homeB.path,
    );

    await cubit.load();
    expect(
      p.normalize(cubit.state.effectiveConfigPath),
      p.normalize(p.join(homeB.path, 'llm.json')),
    );
    expect(cubit.state.config.providers, isEmpty);
  });

  test('setConfigPath with empty string reverts to default', () async {
    final prefs = await SharedPreferences.getInstance();
    final cubit = LlmConfigCubit(
      appSettings: SharedPrefsAppSettingsRepository(prefs),
    );
    await cubit.setConfigPath('   ');

    expect(cubit.state.pathSource, LlmConfigPathSource.defaultPath);
  });
}
