import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/repositories/app_provider_repository.dart';
import 'package:teampilot/services/provider_migration_service.dart';

void main() {
  test('imports legacy llm_config.json into app providers once', () async {
    final root = await Directory.systemTemp.createTemp('provider_migrate_');
    final legacyDir = Directory(p.join(root.path, 'legacy'));
    await legacyDir.create(recursive: true);
    final legacyFile = File(p.join(legacyDir.path, 'llm_config.json'));
    await legacyFile.writeAsString('''
{
  "providers": {
    "deepseek": {
      "type": "api",
      "provider_type": "openai",
      "base_url": "https://api.deepseek.com",
      "api_key": "sk-legacy"
    }
  },
  "models": {
    "m1": {
      "name": "DeepSeek Chat",
      "provider": "deepseek",
      "model": "deepseek-chat",
      "enabled": true
    }
  }
}
''');

    final providerRepo = AppProviderRepository(
      providersFile: AppProviderRepository.providersFileForBasePath(
        p.join(root.path, 'app-data'),
      ),
    );

    final service = ProviderMigrationService(
      providerRepository: providerRepo,
      appDataBasePath: p.join(root.path, 'app-data'),
      homeDirectory: legacyDir.path,
      currentDirectory: legacyDir.path,
    );

    // Point resolver at legacy file via home layout.
    await Directory(p.join(legacyDir.path, '.flashskyai')).create();
    await legacyFile.copy(
      p.join(legacyDir.path, '.flashskyai', 'llm_config.json'),
    );

    final migrated = await service.migrateIfNeeded();
    expect(migrated, isTrue);

    final providers = await providerRepo.loadProviders();
    expect(providers, hasLength(1));
    expect(providers.single.id, 'deepseek');
    expect(providers.single.apiKey, 'sk-legacy');
    expect(providers.single.defaultModel, 'deepseek-chat');
    expect(providers.single.enabledTools, contains(AppProviderTool.flashskyai));

    final commonLlm = File(
      p.join(
        root.path,
        'app-data',
        'config-profiles',
        'common',
        'flashskyai',
        'llm_config.json',
      ),
    );
    expect(await commonLlm.exists(), isTrue);
    expect(await commonLlm.readAsString(), contains('sk-legacy'));

    expect(await service.migrateIfNeeded(), isFalse);

    await root.delete(recursive: true);
  });
}
