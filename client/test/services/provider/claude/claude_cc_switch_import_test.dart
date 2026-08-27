import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/repositories/app_provider_repository.dart';
import 'package:teampilot/services/cli/claude/provider/claude_settings_parser.dart';
import 'package:teampilot/services/cli/codex/provider/codex_cc_switch_import.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/provider/provider_import_service.dart';
import 'package:teampilot/services/storage/app_storage.dart';

void main() {
  group('ClaudeSettingsParser', () {
    test('detects proxy takeover from PROXY_MANAGED auth', () {
      expect(
        ClaudeSettingsParser.detectProxyTakeover({
          'ANTHROPIC_AUTH_TOKEN': ClaudeSettingsParser.proxyManagedToken,
          'ANTHROPIC_BASE_URL': 'http://127.0.0.1:15721',
        }),
        isTrue,
      );
    });

    test('detects proxy takeover from localhost base url', () {
      expect(
        ClaudeSettingsParser.detectProxyTakeover({
          'ANTHROPIC_BASE_URL': 'http://127.0.0.1:15721',
        }),
        isTrue,
      );
    });
  });

  group('Claude import with CC Switch', () {
    late Directory root;
    late String appData;
    late String home;
    late AppProviderRepository repository;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('claude_cc_switch_import_');
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
      'overlays live settings onto current cc-switch provider under proxy takeover',
      () async {
        const rawCurrentId = 'd6f4abb4-f4fe-4420-ac82-e1489cb43d5b';
        final currentId = sanitizeImportedProviderId(rawCurrentId);

        await _writeJson(p.join(home, '.cc-switch', 'settings.json'), {
          'currentProviderClaude': rawCurrentId,
        });
        _writeCcSwitchDb(
          home: home,
          rows: [
            _CcSwitchRow(
              id: rawCurrentId,
              appType: 'claude',
              name: 'OpenCode Go',
              settingsConfig: {
                'env': {
                  'ANTHROPIC_AUTH_TOKEN': 'sk-real-opencode',
                  'ANTHROPIC_BASE_URL': 'https://opencode.ai/zen/go',
                  'ANTHROPIC_MODEL': 'deepseek-v4-flash',
                },
              },
              category: 'third_party',
            ),
          ],
        );

        await _writeJson(p.join(home, '.claude', 'settings.json'), {
          'env': {
            'ANTHROPIC_AUTH_TOKEN': ClaudeSettingsParser.proxyManagedToken,
            'ANTHROPIC_BASE_URL': 'http://127.0.0.1:15721',
            'ANTHROPIC_MODEL': 'deepseek-v4-flash',
            'ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME': 'deepseek-v4-flash',
          },
        });

        final service = ProviderImportService(repository: repository);
        await service.importForCli(CliTool.claude, onlyIfEmpty: false);

        final claude = await repository.loadProviders(CliTool.claude);
        final current = claude.singleWhere((p) => p.id == currentId);
        expect(current.baseUrl, 'http://127.0.0.1:15721');
        expect(current.apiKey, ClaudeSettingsParser.proxyManagedToken);
        expect(
          (current.config['env'] as Map)['ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME'],
          'deepseek-v4-flash',
        );
        expect(
          (current.config['upstreamEnv'] as Map)['ANTHROPIC_AUTH_TOKEN'],
          'sk-real-opencode',
        );
        final meta = current.config['meta'] as Map;
        expect(meta['proxyTakeover'], isTrue);
        expect(meta['importSources'], containsAll(['cc-switch', 'live']));
      },
    );

    test('non-current cc-switch provider keeps catalog settings only', () async {
      const currentRaw = 'current-provider';
      const otherRaw = 'other-provider';

      await _writeJson(p.join(home, '.cc-switch', 'settings.json'), {
        'currentProviderClaude': currentRaw,
      });
      _writeCcSwitchDb(
        home: home,
        rows: [
          _CcSwitchRow(
            id: currentRaw,
            appType: 'claude',
            name: 'Current',
            settingsConfig: {
              'env': {
                'ANTHROPIC_AUTH_TOKEN': 'sk-current',
                'ANTHROPIC_BASE_URL': 'https://current.example.com',
              },
            },
          ),
          _CcSwitchRow(
            id: otherRaw,
            appType: 'claude',
            name: 'Other',
            settingsConfig: {
              'env': {
                'ANTHROPIC_AUTH_TOKEN': 'sk-other',
                'ANTHROPIC_BASE_URL': 'https://other.example.com',
              },
            },
          ),
        ],
      );

      await _writeJson(p.join(home, '.claude', 'settings.json'), {
        'env': {
          'ANTHROPIC_AUTH_TOKEN': ClaudeSettingsParser.proxyManagedToken,
          'ANTHROPIC_BASE_URL': 'http://127.0.0.1:15721',
        },
      });

      final service = ProviderImportService(repository: repository);
      await service.importForCli(CliTool.claude, onlyIfEmpty: false);

      final claude = await repository.loadProviders(CliTool.claude);
      final other = claude.singleWhere(
        (p) => p.id == sanitizeImportedProviderId(otherRaw),
      );
      expect(other.baseUrl, 'https://other.example.com');
      expect(other.apiKey, 'sk-other');
      expect(other.config.containsKey('upstreamEnv'), isFalse);
    });
  });
}

Future<void> _writeJson(String path, Map<String, Object?> body) async {
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsString(jsonEncode(body));
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
