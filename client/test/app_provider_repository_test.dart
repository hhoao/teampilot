import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/repositories/app_provider_repository.dart';

void main() {
  late Directory root;
  late AppProviderRepository repo;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('app_providers_');
    repo = AppProviderRepository(basePath: root.path);
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  test('loads empty list when cli providers file is missing', () async {
    expect(await repo.loadProviders(AppProviderCli.claude), isEmpty);
    expect(await repo.loadProviders(AppProviderCli.codex), isEmpty);
    expect(await repo.loadProviders(AppProviderCli.flashskyai), isEmpty);
  });

  test('saves and reloads providers under cli-specific catalogs', () async {
    const claudeProvider = AppProviderConfig(
      id: 'deepseek',
      cli: AppProviderCli.claude,
      name: 'DeepSeek',
      baseUrl: 'https://api.deepseek.com/anthropic',
      defaultModel: 'deepseek-v4-pro',
    );
    const codexProvider = AppProviderConfig(
      id: 'deepseek',
      cli: AppProviderCli.codex,
      name: 'DeepSeek',
      baseUrl: 'https://api.deepseek.com/v1',
      defaultModel: 'gpt-5.4',
    );

    await repo.saveProviders(AppProviderCli.claude, [claudeProvider]);
    await repo.saveProviders(AppProviderCli.codex, [codexProvider]);

    expect(
      await File(
        p.join(root.path, 'providers', 'providers.json'),
      ).exists(),
      isFalse,
    );
    expect(
      (await repo.loadProviders(AppProviderCli.claude)).single.baseUrl,
      'https://api.deepseek.com/anthropic',
    );
    expect(
      (await repo.loadProviders(AppProviderCli.codex)).single.baseUrl,
      'https://api.deepseek.com/v1',
    );
  });

  test('ignores legacy shared providers catalog', () async {
    final legacyFile = File(p.join(root.path, 'providers', 'providers.json'));
    await legacyFile.parent.create(recursive: true);
    await legacyFile.writeAsString('''
{
  "providers": {
    "legacy": { "id": "legacy", "name": "Legacy" }
  }
}
''');

    expect(await repo.loadProviders(AppProviderCli.claude), isEmpty);
  });

  test('preserves apiKey within the same cli when edit leaves it empty', () async {
    const original = AppProviderConfig(
      id: 'deepseek',
      cli: AppProviderCli.claude,
      name: 'DeepSeek',
      apiKey: 'sk-secret',
    );
    await repo.saveProviders(AppProviderCli.claude, [original]);

    await repo.saveProviders(AppProviderCli.claude, [
      original.copyWith(name: 'DeepSeek Renamed', apiKey: ''),
    ]);

    final loaded = await repo.loadProviders(AppProviderCli.claude);
    expect(loaded.single.apiKey, 'sk-secret');
    expect(loaded.single.name, 'DeepSeek Renamed');
  });

  test('writes native codex files for codex providers only', () async {
    const provider = AppProviderConfig(
      id: 'deepseek',
      cli: AppProviderCli.codex,
      name: 'DeepSeek',
      apiKey: 'sk-test',
      baseUrl: 'https://api.deepseek.com/v1',
      defaultModel: 'gpt-5.4',
    );

    await repo.saveProviders(AppProviderCli.codex, [provider]);

    expect(
      await File(
        p.join(root.path, 'providers', 'codex', 'deepseek', 'auth.json'),
      ).exists(),
      isTrue,
    );
    expect(
      await File(
        p.join(root.path, 'providers', 'codex', 'deepseek', 'config.toml'),
      ).exists(),
      isTrue,
    );
  });

  test('writes app flashskyai llm_config.json from flashskyai catalog', () async {
    const provider = AppProviderConfig(
      id: 'deepseek',
      cli: AppProviderCli.flashskyai,
      name: 'DeepSeek',
      apiKey: 'sk-test',
      baseUrl: 'https://api.deepseek.com',
      defaultModel: 'deepseek-chat',
      config: {'provider_type': 'openai'},
    );

    await repo.saveProviders(AppProviderCli.flashskyai, [provider]);

    final appFile = File(
      p.join(
        root.path,
        'config-profiles',
        'flashskyai',
        'llm_config.json',
      ),
    );
    expect(await appFile.exists(), isTrue);
    final raw = jsonDecode(await appFile.readAsString()) as Map;
    expect((raw['providers'] as Map).keys, contains('deepseek'));
  });

  test('removes stale codex provider directories', () async {
    const provider = AppProviderConfig(
      id: 'deepseek',
      cli: AppProviderCli.codex,
      name: 'DeepSeek',
      apiKey: 'sk-test',
      baseUrl: 'https://api.deepseek.com/v1',
    );
    await repo.saveProviders(AppProviderCli.codex, [provider]);

    expect(
      await Directory(
        p.join(root.path, 'providers', 'codex', 'deepseek'),
      ).exists(),
      isTrue,
    );

    await repo.saveProviders(AppProviderCli.codex, const []);

    expect(
      await Directory(
        p.join(root.path, 'providers', 'codex', 'deepseek'),
      ).exists(),
      isFalse,
    );
  });
}
