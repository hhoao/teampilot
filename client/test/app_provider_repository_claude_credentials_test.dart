import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/repositories/app_provider_repository.dart';
import 'package:teampilot/services/app_storage.dart';
import 'package:teampilot/services/claude_provider_credentials_service.dart';
import 'package:teampilot/services/runtime_storage_context.dart';

import 'support/in_memory_filesystem.dart';

void main() {
  late InMemoryFilesystem fs;
  late AppProviderRepository repository;
  const base = '/data/tp';

  setUp(() {
    fs = InMemoryFilesystem();
    repository = AppProviderRepository(
      basePath: base,
      fs: fs,
      claudeCredentialsService: ClaudeProviderCredentialsService(
        fs: fs,
        basePath: base,
      ),
    );
  });

  tearDown(() {
    RuntimeStorageContext.resetForTesting();
  });

  test('removes stale claude provider credential dirs on save', () async {
    await fs.ensureDir(fs.pathContext.join(base, 'providers', 'claude', 'old-id'));
    await fs.writeString(
      fs.pathContext.join(base, 'providers', 'claude', 'old-id', '.credentials.json'),
      '{"claudeAiOauth":{"accessToken":"old"}}',
    );
    await fs.writeString(
      fs.pathContext.join(base, 'providers', 'claude', 'providers.json'),
      jsonEncode({
        'providers': {
          'work': {
            'id': 'work',
            'cli': 'claude',
            'name': 'Work',
            'category': 'official',
            'config': {'env': {}},
          },
        },
      }),
    );

    await repository.saveProviders(AppProviderCli.claude, [
      const AppProviderConfig(
        id: 'work',
        cli: AppProviderCli.claude,
        name: 'Work',
        category: AppProviderCategory.official,
        config: {'env': {}},
      ),
    ]);

    expect(
      (await fs.stat(fs.pathContext.join(base, 'providers', 'claude', 'old-id'))).exists,
      isFalse,
    );
  });

  test('load probes official provider credential status from disk', () async {
    await fs.writeString(
      fs.pathContext.join(base, 'providers', 'claude', 'providers.json'),
      jsonEncode({
        'providers': {
          'work': {
            'id': 'work',
            'cli': 'claude',
            'name': 'Work',
            'category': 'official',
            'config': {'env': {}},
            'credentialStatus': 'missing',
          },
        },
      }),
    );
    await fs.writeString(
      fs.pathContext.join(base, 'providers', 'claude', 'work', '.credentials.json'),
      '{"claudeAiOauth":{"accessToken":"work"}}',
    );

    final providers = await repository.loadProviders(AppProviderCli.claude);
    expect(providers.single.hasClaudeCredentialsReady, isTrue);
  });

  test(
    'load imports global credentials for official provider when missing locally',
    () async {
      const home = '/home/user';
      RuntimeStorageContext.installForTesting(
        filesystem: fs,
        paths: AppPaths(base),
        home: home,
        cwd: '/tmp',
      );
      await fs.writeString(
        fs.pathContext.join(base, 'providers', 'claude', 'providers.json'),
        jsonEncode({
          'providers': {
            'default': {
              'id': 'default',
              'cli': 'claude',
              'name': 'Default',
              'category': 'official',
              'config': {'env': {}},
              'credentialStatus': 'missing',
            },
          },
        }),
      );
      await fs.writeString(
        fs.pathContext.join(home, '.claude', '.credentials.json'),
        '{"claudeAiOauth":{"accessToken":"global"}}',
      );

      final providers = await repository.loadProviders(AppProviderCli.claude);
      expect(providers.single.hasClaudeCredentialsReady, isTrue);
      expect(
        (await fs.stat(
          fs.pathContext.join(
            base,
            'providers',
            'claude',
            'default',
            '.credentials.json',
          ),
        )).isFile,
        isTrue,
      );
    },
  );

  test('load does not overwrite existing provider credentials from global', () async {
    const home = '/home/user';
    RuntimeStorageContext.installForTesting(
      filesystem: fs,
      paths: AppPaths(base),
      home: home,
      cwd: '/tmp',
    );
    await fs.writeString(
      fs.pathContext.join(base, 'providers', 'claude', 'providers.json'),
      jsonEncode({
        'providers': {
          'default': {
            'id': 'default',
            'cli': 'claude',
            'name': 'Default',
            'category': 'official',
            'config': {'env': {}},
            'credentialStatus': 'ready',
          },
        },
      }),
    );
    await fs.writeString(
      fs.pathContext.join(
        base,
        'providers',
        'claude',
        'default',
        '.credentials.json',
      ),
      '{"claudeAiOauth":{"accessToken":"local"}}',
    );
    await fs.writeString(
      fs.pathContext.join(home, '.claude', '.credentials.json'),
      '{"claudeAiOauth":{"accessToken":"global"}}',
    );

    await repository.loadProviders(AppProviderCli.claude);

    final bytes = await fs.readBytes(
      fs.pathContext.join(
        base,
        'providers',
        'claude',
        'default',
        '.credentials.json',
      ),
    );
    expect(bytes, isNotNull);
    expect(String.fromCharCodes(bytes!), contains('local'));
  });
}
