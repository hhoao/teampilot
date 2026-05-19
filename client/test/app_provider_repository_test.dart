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
    repo = AppProviderRepository(
      providersFile: File(p.join(root.path, 'providers', 'providers.json')),
    );
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  test('loads empty list when file is missing', () async {
    expect(await repo.loadProviders(), isEmpty);
  });

  test('saves and reloads multiple providers', () async {
    final now = DateTime.utc(2026, 5, 18).millisecondsSinceEpoch;
    final providers = [
      AppProviderConfig(
        id: 'deepseek',
        name: 'DeepSeek',
        baseUrl: 'https://api.deepseek.com',
        defaultModel: 'deepseek-chat',
        enabledTools: const [AppProviderTool.flashskyai],
        createdAt: now,
        updatedAt: now,
      ),
      AppProviderConfig(
        id: 'openai',
        name: 'OpenAI',
        enabledTools: const [AppProviderTool.codex, AppProviderTool.claude],
        createdAt: now,
        updatedAt: now,
      ),
    ];

    await repo.saveProviders(providers);
    final loaded = await repo.loadProviders();

    expect(loaded, hasLength(2));
    expect(loaded.map((p) => p.id).toSet(), {'deepseek', 'openai'});
    expect(
      loaded.firstWhere((p) => p.id == 'deepseek').baseUrl,
      'https://api.deepseek.com',
    );
  });

  test('preserves unknown top-level and provider fields', () async {
    final file = repo.providersFile;
    await file.parent.create(recursive: true);
    await file.writeAsString('''
{
  "schemaVersion": 2,
  "providers": {
    "demo": {
      "id": "demo",
      "name": "Demo",
      "enabledTools": ["flashskyai"],
      "toolConfigs": {
        "flashskyai": { "custom_flag": true }
      },
      "future_flag": "keep-me",
      "createdAt": 1,
      "updatedAt": 1
    }
  }
}
''');

    final loaded = await repo.loadProviders();
    expect(loaded.single.unknownFields['future_flag'], 'keep-me');
    expect(
      loaded.single.toolConfigs.flashskyai.unknownFields['custom_flag'],
      true,
    );

    final raw = jsonDecode(await file.readAsString()) as Map<String, Object?>;
    expect(raw['schemaVersion'], 2);
  });

  test('keeps provider id stable when display name changes', () async {
    final now = DateTime.utc(2026, 5, 18).millisecondsSinceEpoch;
    await repo.saveProviders([
      AppProviderConfig(
        id: 'stable-id',
        name: 'Original Name',
        createdAt: now,
        updatedAt: now,
      ),
    ]);

    final renamed = AppProviderConfig(
      id: 'stable-id',
      name: 'Renamed Provider',
      createdAt: now,
      updatedAt: now + 1,
    );
    await repo.saveProviders([renamed]);

    final loaded = await repo.loadProviders();
    expect(loaded.single.id, 'stable-id');
    expect(loaded.single.name, 'Renamed Provider');
  });

  test(
    'writes native tool configs under providers tool provider dirs',
    () async {
      final provider = AppProviderConfig(
        id: 'deepseek',
        name: 'DeepSeek',
        apiKey: 'sk-test',
        baseUrl: 'https://api.deepseek.com',
        defaultModel: 'deepseek-chat',
        enabledTools: const [AppProviderTool.codex, AppProviderTool.claude],
      );

      await repo.saveProviders([provider]);

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
      expect(
        await Directory(p.join(root.path, 'providers', 'claude')).exists(),
        isFalse,
      );
    },
  );

  test('writes common flashskyai llm_config.json', () async {
    await repo.saveProviders([
      AppProviderConfig(
        id: 'deepseek',
        name: 'DeepSeek',
        apiKey: 'sk-test',
        baseUrl: 'https://api.deepseek.com',
        defaultModel: 'deepseek-chat',
        enabledTools: const [AppProviderTool.flashskyai],
      ),
    ]);

    final commonFile = File(
      p.join(
        root.path,
        'config-profiles',
        'common',
        'flashskyai',
        'llm_config.json',
      ),
    );
    expect(await commonFile.exists(), isTrue);
    expect(await commonFile.readAsString(), contains('deepseek'));
  });

  test(
    'clears common flashskyai llm_config.json when no flashskyai providers remain',
    () async {
      await repo.saveProviders([
        const AppProviderConfig(
          id: 'deepseek',
          name: 'DeepSeek',
          apiKey: 'sk-test',
          baseUrl: 'https://api.deepseek.com',
          defaultModel: 'deepseek-chat',
          enabledTools: [AppProviderTool.flashskyai],
        ),
      ]);

      final commonFile = File(
        p.join(
          root.path,
          'config-profiles',
          'common',
          'flashskyai',
          'llm_config.json',
        ),
      );
      expect(await commonFile.readAsString(), contains('deepseek'));

      await repo.saveProviders(const []);

      final raw = jsonDecode(await commonFile.readAsString()) as Map;
      expect(raw['providers'], isEmpty);
      expect(raw['models'], isEmpty);
    },
  );

  test('removes stale native tool config directories', () async {
    const provider = AppProviderConfig(
      id: 'deepseek',
      name: 'DeepSeek',
      apiKey: 'sk-test',
      baseUrl: 'https://api.deepseek.com',
      defaultModel: 'deepseek-chat',
      enabledTools: [AppProviderTool.codex, AppProviderTool.claude],
    );
    await repo.saveProviders([provider]);
    expect(
      await Directory(
        p.join(root.path, 'providers', 'codex', 'deepseek'),
      ).exists(),
      isTrue,
    );
    expect(
      await Directory(p.join(root.path, 'providers', 'claude')).exists(),
      isFalse,
    );

    await repo.saveProviders([
      provider.copyWith(enabledTools: const [AppProviderTool.flashskyai]),
    ]);

    expect(
      await Directory(
        p.join(root.path, 'providers', 'codex', 'deepseek'),
      ).exists(),
      isFalse,
    );
    expect(
      await Directory(p.join(root.path, 'providers', 'claude')).exists(),
      isFalse,
    );
  });
}
