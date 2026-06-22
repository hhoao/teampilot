import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/repositories/app_provider_repository.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/provider/opencode/opencode_data_layout.dart';
import 'package:teampilot/services/provider/provider_import_service.dart';
import 'package:teampilot/services/provider/provider_migration_service.dart';
import 'package:teampilot/services/storage/runtime_storage_context.dart';

void main() {
  late Directory root;
  late String appData;
  late String home;
  late AppProviderRepository repository;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('provider_import_');
    appData = p.join(root.path, 'app-data');
    home = p.join(root.path, 'home');
    await Directory(home).create(recursive: true);
    RuntimeStorageContext.installForTesting(
      filesystem: LocalFilesystem(),
      paths: AppPaths(appData),
      home: home,
      cwd: root.path,
    );
    repository = AppProviderRepository(basePath: appData);
  });

  tearDown(() async {
    RuntimeStorageContext.resetForTesting();
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  test('imports flashskyai providers from cli install llm_config', () async {
    final install = p.join(root.path, 'flashskyai-install');
    final executable = p.join(install, 'dist', 'flashskyai');
    final llmConfig = File(p.join(install, 'llm', 'llm_config.json'));
    await File(executable).parent.create(recursive: true);
    await File(executable).writeAsString('');
    await llmConfig.parent.create(recursive: true);
    await llmConfig.writeAsString(
      jsonEncode({
        'providers': {
          'packycode': {
            'type': 'api',
            'provider_type': 'openai',
            'base_url': 'https://api.packycode.com/v1',
            'api_key': 'fk-flash',
          },
        },
        'models': {
          'packy-default': {
            'name': 'Packy Default',
            'provider': 'packycode',
            'model': 'gpt-5',
            'enabled': true,
          },
        },
      }),
    );

    final service = ProviderImportService(
      repository: repository,
      flashskyaiExecutablePath: executable,
    );

    final result = await service.importForCli(
      CliTool.flashskyai,
      onlyIfEmpty: false,
    );

    expect(result.added, 1);
    final imported = await repository.loadProviders(CliTool.flashskyai);
    expect(imported.single.id, 'packycode');
    expect(imported.single.apiKey, 'fk-flash');
    expect(imported.single.baseUrl, 'https://api.packycode.com/v1');
    expect(imported.single.defaultModel, 'gpt-5');
  });

  test(
    'imports claude official credentials from global home during provider import',
    () async {
      await _writeJson(
        p.join(home, '.claude', 'settings.json'),
        const {'env': {}},
      );
      await _writeJson(
        p.join(home, '.claude', '.credentials.json'),
        const {
          'claudeAiOauth': {'accessToken': 'global-oauth'},
        },
      );

      final service = ProviderImportService(repository: repository);
      final result = await service.importForCli(
        CliTool.claude,
        onlyIfEmpty: false,
      );

      expect(result.added, 1);
      final claude = await repository.loadProviders(CliTool.claude);
      final official = claude.singleWhere((p) => p.id == 'default');
      expect(official.category, AppProviderCategory.official);
      expect(official.hasClaudeCredentialsReady, isTrue);
      expect(
        await File(
          p.join(
            appData,
            'providers',
            'claude',
            'default',
            '.credentials.json',
          ),
        ).exists(),
        isTrue,
      );
    },
  );

  test(
    'imports claude from live and cc-switch then mirrors missing ids to flashskyai',
    () async {
      await _writeJson(
        p.join(home, '.claude', 'settings-packycode.json'),
        {
          'env': {
            'ANTHROPIC_BASE_URL': 'https://api.packycode.com',
            'ANTHROPIC_AUTH_TOKEN': 'sk-live',
            'ANTHROPIC_MODEL': 'claude-live',
          },
        },
      );
      await repository.saveProviders(CliTool.flashskyai, [
        const AppProviderConfig(
          id: 'packycode',
          cli: CliTool.flashskyai,
          name: 'Existing Packy',
          baseUrl: 'https://api.packycode.com',
        ),
      ]);
      _writeCcSwitchDb(
        home: home,
        rows: [
          _CcSwitchRow(
            id: 'router-plus',
            appType: 'claude',
            name: 'Router Plus',
            settingsConfig: {
              'env': {
                'ANTHROPIC_BASE_URL': 'https://router.example.com',
                'ANTHROPIC_API_KEY': 'sk-db',
                'ANTHROPIC_MODEL': 'claude-db',
              },
            },
            category: 'aggregator',
          ),
        ],
      );

      final service = ProviderImportService(repository: repository);

      final result = await service.importForCli(
        CliTool.claude,
        onlyIfEmpty: false,
      );

      expect(result.added, 2);
      expect(result.mirroredToFlashskyai, 1);
      expect(result.mirrorSkipped, 1);

      final claude = await repository.loadProviders(CliTool.claude);
      expect(claude.map((p) => p.id), containsAll(['packycode', 'router-plus']));
      expect(
        claude.singleWhere((p) => p.id == 'router-plus').apiKey,
        'sk-db',
      );

      final flashskyai = await repository.loadProviders(
        CliTool.flashskyai,
      );
      expect(flashskyai.map((p) => p.id), containsAll(['packycode', 'router-plus']));
      expect(flashskyai.where((p) => p.id == 'packycode'), hasLength(1));
      final mirrored = flashskyai.singleWhere((p) => p.id == 'router-plus');
      expect(mirrored.baseUrl, 'https://router.example.com');
      expect(mirrored.apiKey, 'sk-db');
      final mirroredModels = mirrored.config['models'] as Map;
      expect(mirroredModels, contains('claude-db'));
      expect(mirroredModels['claude-db'], {
        'name': 'claude-db',
        'provider': 'router-plus',
        'model': 'claude-db',
        'enabled': true,
      });
    },
  );

  test('mirrors codex provider with same baseUrl when id differs', () async {
    await repository.saveProviders(CliTool.flashskyai, [
      const AppProviderConfig(
        id: 'same-url-existing',
        cli: CliTool.flashskyai,
        name: 'Same URL Existing',
        baseUrl: 'https://same.example.com/v1',
      ),
    ]);
    await _writeJson(
      p.join(home, '.codex', 'auth-deepseek.json'),
      {'OPENAI_API_KEY': 'sk-codex'},
    );
    await _writeText(
      p.join(home, '.codex', 'config-deepseek.toml'),
      '''
model_provider = "deepseek"
model = "deepseek-chat"

[model_providers.deepseek]
base_url = "https://same.example.com/v1"
wire_api = "chat"
''',
    );

    final service = ProviderImportService(repository: repository);

    final result = await service.importForCli(
      CliTool.codex,
      onlyIfEmpty: false,
    );

    expect(result.mirroredToFlashskyai, 1);
    expect(result.mirrorSkipped, 0);
    final flashskyai = await repository.loadProviders(
      CliTool.flashskyai,
    );
    expect(flashskyai.map((p) => p.id), containsAll(['same-url-existing', 'deepseek']));
    final mirrored = flashskyai.singleWhere((p) => p.id == 'deepseek');
    final mirroredModels = mirrored.config['models'] as Map;
    expect(mirroredModels, contains('deepseek-chat'));
  });

  test(
    'does not mirror models that already exist in flashskyai catalog',
    () async {
      await repository.saveProviders(CliTool.flashskyai, [
        const AppProviderConfig(
          id: 'flashskyai-native',
          cli: CliTool.flashskyai,
          name: 'FlashskyAI Native',
          baseUrl: 'https://native.example.com',
          defaultModel: 'deepseek-chat',
          config: {
            'provider_type': 'openai',
            'models': {
              'deepseek-chat': {
                'name': 'deepseek-chat',
                'provider': 'flashskyai-native',
                'model': 'deepseek-chat',
                'enabled': true,
              },
            },
          },
        ),
      ]);
      await _writeJson(
        p.join(home, '.codex', 'auth-deepseek.json'),
        {'OPENAI_API_KEY': 'sk-codex'},
      );
      await _writeText(
        p.join(home, '.codex', 'config-deepseek.toml'),
        '''
model_provider = "deepseek"
model = "deepseek-chat"

[model_providers.deepseek]
base_url = "https://codex.example.com/v1"
wire_api = "chat"
''',
      );

      final service = ProviderImportService(repository: repository);

      final result = await service.importForCli(
        CliTool.codex,
        onlyIfEmpty: false,
      );

      expect(result.mirroredToFlashskyai, 1);
      final flashskyai = await repository.loadProviders(
        CliTool.flashskyai,
      );
      final mirrored = flashskyai.singleWhere((p) => p.id == 'deepseek');
      expect(mirrored.config['models'], isNot(contains('deepseek-chat')));

      final llmConfig = jsonDecode(
        await File(
          p.join(
            appData,
            'cli-defaults',
            'flashskyai',
            'llm_config.json',
          ),
        ).readAsString(),
      ) as Map;
      final model =
          (llmConfig['models'] as Map)['deepseek-chat'] as Map<String, Object?>;
      expect(model['provider'], 'flashskyai-native');
      expect(llmConfig['models'] as Map, isNot(contains('deepseek-default')));
    },
  );

  test(
    'imports cursor account from global auth during provider import',
    () async {
      await _writeJson(
        p.join(home, '.config', 'cursor', 'auth.json'),
        const {
          'accessToken': 'cursor-at',
          'refreshToken': 'cursor-rt',
        },
      );
      await _writeJson(
        p.join(home, '.cursor', 'cli-config.json'),
        const {
          'authInfo': {'userId': 'u1', 'authId': 'a1'},
        },
      );

      final service = ProviderImportService(repository: repository);
      final result = await service.importForCli(
        CliTool.cursor,
        onlyIfEmpty: false,
      );

      expect(result.added, 1);
      await repository.loadProviders(
        CliTool.cursor,
        importCredentialsFromGlobal: true,
      );
      final cursor = await repository.loadProviders(CliTool.cursor);
      final account = cursor.singleWhere((p) => p.id == 'cursor-account');
      expect(account.isOfficial, isTrue);
      expect(
        await File(
          p.join(
            appData,
            'providers',
            'cursor',
            'cursor-account',
            'home',
            '.config',
            'cursor',
            'auth.json',
          ),
        ).exists(),
        isTrue,
      );
    },
  );

  test('imports opencode providers from global auth.json', () async {
    const layout = OpencodeDataLayout();
    final authDir = layout.globalDataHome(home);
    await _writeJson(
      layout.authJsonPath(authDir),
      const {
        'openai': {'type': 'api', 'key': 'sk-openai'},
        'anthropic': {'type': 'api', 'key': 'sk-anthropic'},
      },
    );
    await _writeJson(
      layout.opencodeConfigPath(layout.globalConfigHome(home)),
      const {'model': 'openai/gpt-4o'},
    );

    final service = ProviderImportService(repository: repository);
    final result = await service.importForCli(
      CliTool.opencode,
      onlyIfEmpty: false,
    );

    expect(result.added, 2);
    await repository.loadProviders(
      CliTool.opencode,
      importCredentialsFromGlobal: true,
    );
    final opencode = await repository.loadProviders(CliTool.opencode);
    expect(opencode.map((p) => p.id), containsAll(['openai', 'anthropic']));
    final openai = opencode.singleWhere((p) => p.id == 'openai');
    expect(openai.defaultModel, 'gpt-4o');
    expect(
      await File(
        p.join(
          appData,
          'providers',
          'opencode',
          'openai',
          'xdg-data',
          'opencode',
          'auth.json',
        ),
      ).exists(),
      isTrue,
    );
  });

  test('startup migration imports only empty cli catalogs', () async {
    await repository.saveProviders(CliTool.claude, [
      const AppProviderConfig(
        id: 'existing',
        cli: CliTool.claude,
        name: 'Existing',
      ),
    ]);
    await _writeJson(
      p.join(home, '.claude', 'settings-new.json'),
      {
        'env': {'ANTHROPIC_API_KEY': 'sk-new'},
      },
    );
    await _writeJson(
      p.join(home, '.codex', 'auth-codex-new.json'),
      {'OPENAI_API_KEY': 'sk-codex'},
    );

    final service = ProviderMigrationService(providerRepository: repository);

    expect(await service.migrateIfNeeded(), isTrue);
    expect(
      (await repository.loadProviders(CliTool.claude)).map((p) => p.id),
      ['existing'],
    );
    expect(
      (await repository.loadProviders(CliTool.codex)).map((p) => p.id),
      contains('codex-new'),
    );
  });
}

Future<void> _writeJson(String path, Map<String, Object?> json) async {
  await _writeText(path, jsonEncode(json));
}

Future<void> _writeText(String path, String body) async {
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsString(body);
}

void _writeCcSwitchDb({
  required String home,
  required List<_CcSwitchRow> rows,
}) {
  final dbFile = File(p.join(home, '.cc-switch', 'cc-switch.db'));
  dbFile.parent.createSync(recursive: true);
  final db = sqlite3.open(dbFile.path);
  try {
    db.execute('''
CREATE TABLE providers (
  id TEXT NOT NULL,
  app_type TEXT NOT NULL,
  name TEXT NOT NULL,
  settings_config TEXT NOT NULL,
  website_url TEXT,
  category TEXT,
  created_at INTEGER,
  notes TEXT,
  icon TEXT,
  icon_color TEXT,
  meta TEXT NOT NULL DEFAULT '{}',
  PRIMARY KEY (id, app_type)
)
''');
    final stmt = db.prepare('''
INSERT INTO providers (
  id, app_type, name, settings_config, website_url, category,
  created_at, notes, icon, icon_color, meta
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
''');
    try {
      for (final row in rows) {
        stmt.execute([
          row.id,
          row.appType,
          row.name,
          jsonEncode(row.settingsConfig),
          row.websiteUrl,
          row.category,
          row.createdAt,
          row.notes,
          row.icon,
          row.iconColor,
          jsonEncode(row.meta),
        ]);
      }
    } finally {
      stmt.close();
    }
  } finally {
    db.close();
  }
}

class _CcSwitchRow {
  const _CcSwitchRow({
    required this.id,
    required this.appType,
    required this.name,
    required this.settingsConfig,
    this.category,
  });

  final String id;
  final String appType;
  final String name;
  final Map<String, Object?> settingsConfig;
  String? get websiteUrl => null;
  final String? category;
  int get createdAt => 0;
  String? get notes => null;
  String? get icon => null;
  String? get iconColor => null;
  Map<String, Object?> get meta => const {};
}
