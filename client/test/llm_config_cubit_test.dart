import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:teampilot/cubits/llm_config_cubit.dart';
import 'package:teampilot/repositories/app_settings_repository.dart';
import 'package:teampilot/repositories/llm_config_repository.dart';
import 'package:teampilot/services/llm_config_path_resolver.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = await Directory.systemTemp.createTemp('llm_cubit_test_');
  });

  tearDown(() async {
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
      currentDirectory: tmp.path,
      homeDirectory: '/home/test',
      executableResolver: () => '/opt/flashskyai/dist/flashskyai',
      repositoryFactory: (path) => LlmConfigRepository(File(path)),
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
      currentDirectory: tmp.path,
      homeDirectory: '/home/test',
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
      currentDirectory: tmp.path,
      homeDirectory: '/home/test',
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
      currentDirectory: tmp.path,
      homeDirectory: '/home/test',
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
      currentDirectory: tmp.path,
      homeDirectory: '/home/test',
    );
    await cubit.setConfigPath(null);

    expect(cubit.state.pathSource, LlmConfigPathSource.defaultPath);
    expect(cubit.state.configPathOverride, '');
    expect(await SharedPrefsAppSettingsRepository(prefs).loadLlmConfigPathOverride(), isNull);
  });

  test('setConfigPath with empty string reverts to default', () async {
    final prefs = await SharedPreferences.getInstance();
    final cubit = LlmConfigCubit(
      appSettings: SharedPrefsAppSettingsRepository(prefs),
      currentDirectory: tmp.path,
      homeDirectory: '/home/test',
    );
    await cubit.setConfigPath('   ');

    expect(cubit.state.pathSource, LlmConfigPathSource.defaultPath);
  });
}
