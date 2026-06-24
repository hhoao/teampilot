import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/repositories/app_provider_repository.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/provider/codex/codex_cc_switch_import.dart';
import 'package:teampilot/services/provider/codex/codex_toml_parser.dart';
import 'package:teampilot/services/provider/provider_import_service.dart';
import 'package:teampilot/services/storage/app_storage.dart';

void main() {
  group('CodexTomlParser', () {
    test('detects proxy takeover from PROXY_MANAGED auth', () {
      expect(
        CodexTomlParser.detectProxyTakeover(
          liveToml: '',
          liveAuth: {'OPENAI_API_KEY': 'PROXY_MANAGED'},
        ),
        isTrue,
      );
    });

    test('parses nested base_url', () {
      const toml = '''
model = "deepseek-v4-flash"
[model_providers.custom]
base_url = "http://127.0.0.1:15721/v1"
''';
      final parts = CodexTomlParser.parse(toml);
      expect(parts.model, 'deepseek-v4-flash');
      expect(parts.baseUrl, 'http://127.0.0.1:15721/v1');
    });
  });

  group('Codex import with CC Switch', () {
    late Directory root;
    late String appData;
    late String home;
    late AppProviderRepository repository;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('codex_cc_switch_import_');
      appData = p.join(root.path, 'app-data');
      home = p.join(root.path, 'home');
      await Directory(home).create(recursive: true);
      AppStorage.installForTesting(
        filesystem: LocalFilesystem(),
        paths: AppPaths(appData),
        home: home,
        cwd: root.path,
      );
      repository = AppProviderRepository(basePath: appData);
    });

    tearDown(() async {
      AppStorage.resetForTesting();
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    test(
      'overlays live config onto current cc-switch provider under proxy takeover',
      () async {
        const rawCurrentId = '7ffd3083-067f-4349-9e7c-716892da85fe';
        final currentId = sanitizeImportedProviderId(rawCurrentId);

        await _writeJson(p.join(home, '.cc-switch', 'config.json'), {
          'current_provider_codex': rawCurrentId,
        });
        _writeCcSwitchDb(
          home: home,
          rows: [
            _CcSwitchRow(
              id: rawCurrentId,
              appType: 'codex',
              name: 'DeepSeek',
              settingsConfig: {
                'auth': {'OPENAI_API_KEY': 'sk-real-deepseek'},
                'config': '''
model_provider = "custom"
model = "deepseek-v4-flash"

[model_providers.custom]
base_url = "https://api.deepseek.com"
wire_api = "responses"
''',
              },
              category: 'cn_official',
            ),
          ],
        );

        await _writeJson(p.join(home, '.codex', 'auth.json'), {
          'OPENAI_API_KEY': 'PROXY_MANAGED',
        });
        await _writeText(
          p.join(home, '.codex', 'config.toml'),
          '''
model_provider = "custom"
model = "deepseek-v4-flash"

[model_providers.custom]
base_url = "http://127.0.0.1:15721/v1"
experimental_bearer_token = "PROXY_MANAGED"

[features]
rmcp_client = true
''',
        );

        final service = ProviderImportService(repository: repository);
        await service.importForCli(CliTool.codex, onlyIfEmpty: false);

        final codex = await repository.loadProviders(CliTool.codex);
        final current = codex.singleWhere((p) => p.id == currentId);
        expect(current.baseUrl, 'http://127.0.0.1:15721/v1');
        expect(current.apiKey, 'sk-real-deepseek');
        expect(current.config['configToml'], contains('15721'));
        expect(current.config['configToml'], contains('[features]'));
        expect(
          current.config['upstreamConfigToml'],
          contains('api.deepseek.com'),
        );
        final meta = current.config['meta'] as Map;
        expect(meta['proxyTakeover'], isTrue);

        final defaultProvider = codex.singleWhere((p) => p.id == 'default');
        expect(defaultProvider.config['configToml'], contains('15721'));
      },
    );

    test('non-current cc-switch provider keeps catalog toml only', () async {
      const currentRaw = 'current-provider';
      const otherRaw = 'other-provider';

      await _writeJson(p.join(home, '.cc-switch', 'config.json'), {
        'current_provider_codex': currentRaw,
      });
      _writeCcSwitchDb(
        home: home,
        rows: [
          _CcSwitchRow(
            id: currentRaw,
            appType: 'codex',
            name: 'Current',
            settingsConfig: {
              'auth': {'OPENAI_API_KEY': 'sk-a'},
              'config':
                  'model = "a"\n[model_providers.custom]\nbase_url = "http://127.0.0.1:15721/v1"\n',
            },
          ),
          _CcSwitchRow(
            id: otherRaw,
            appType: 'codex',
            name: 'Other',
            settingsConfig: {
              'auth': {'OPENAI_API_KEY': 'sk-b'},
              'config':
                  'model = "b"\n[model_providers.custom]\nbase_url = "https://other.example.com/v1"\n',
            },
          ),
        ],
      );

      await _writeJson(p.join(home, '.codex', 'auth.json'), {
        'OPENAI_API_KEY': 'PROXY_MANAGED',
      });
      await _writeText(
        p.join(home, '.codex', 'config.toml'),
        'model = "a"\n[model_providers.custom]\nbase_url = "http://127.0.0.1:15721/v1"\n',
      );

      final service = ProviderImportService(repository: repository);
      await service.importForCli(CliTool.codex, onlyIfEmpty: false);

      final codex = await repository.loadProviders(CliTool.codex);
      final other = codex.singleWhere(
        (p) => p.id == sanitizeImportedProviderId(otherRaw),
      );
      expect(other.baseUrl, 'https://other.example.com/v1');
      expect(other.config['upstreamConfigToml'], isNull);
    });
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
  is_current INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (id, app_type)
)
''');
    final stmt = db.prepare('''
INSERT INTO providers (
  id, app_type, name, settings_config, website_url, category,
  created_at, notes, icon, icon_color, meta, is_current
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
          row.isCurrent ? 1 : 0,
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
  bool get isCurrent => false;
}
