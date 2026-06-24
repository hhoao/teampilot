import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/repositories/app_provider_repository.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/provider/claude/claude_provider_credentials_service.dart';
import 'package:teampilot/services/provider/credential_binding.dart';

import '../support/in_memory_filesystem.dart';

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
        resolveHomeDirectory: () => '/home/user',
      ),
    );
  });

  tearDown(() {
    AppStorage.resetForTesting();
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

    await repository.saveProviders(CliTool.claude, [
      const AppProviderConfig(
        id: 'work',
        cli: CliTool.claude,
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

  test('load probes linked official credentials from global home', () async {
    const home = '/home/user';
    AppStorage.installForTesting(
      filesystem: fs,
      paths: AppPaths(base),
      home: home,
      cwd: '/tmp',
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
            'config': {
              'env': {},
              credentialBindingConfigKey: 'linked',
            },
            'credentialStatus': 'missing',
          },
        },
      }),
    );
    await fs.writeString(
      fs.pathContext.join(home, '.claude', '.credentials.json'),
      '{"claudeAiOauth":{"accessToken":"work"}}',
    );

    final providers = await repository.loadProviders(CliTool.claude);
    expect(providers.single.hasClaudeCredentialsReady, isTrue);
    expect(
      fs.symlinks[fs.pathContext.join(
        base,
        'providers',
        'claude',
        'work',
        '.credentials.json',
      )],
      fs.pathContext.join(home, '.claude', '.credentials.json'),
    );
  });

  test(
    'load does not import global credentials unless explicitly requested',
    () async {
      const home = '/home/user';
      AppStorage.installForTesting(
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
              'config': {
                'env': {},
                credentialBindingConfigKey: 'isolated',
              },
              'credentialStatus': 'missing',
            },
          },
        }),
      );
      await fs.writeString(
        fs.pathContext.join(home, '.claude', '.credentials.json'),
        '{"claudeAiOauth":{"accessToken":"global"}}',
      );

      final providers = await repository.loadProviders(CliTool.claude);
      expect(providers.single.hasClaudeCredentialsReady, isFalse);
      expect(
        (await fs.stat(
          fs.pathContext.join(
            base,
            'providers',
            'claude',
            'default',
            '.credentials.json',
          ),
        )).exists,
        isFalse,
      );
    },
  );

  test(
    'load imports global credentials when importCredentialsFromGlobal is true',
    () async {
      const home = '/home/user';
      AppStorage.installForTesting(
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
              'config': {
                'env': {},
                credentialBindingConfigKey: 'linked',
              },
              'credentialStatus': 'missing',
            },
          },
        }),
      );
      await fs.writeString(
        fs.pathContext.join(home, '.claude', '.credentials.json'),
        '{"claudeAiOauth":{"accessToken":"global"}}',
      );

      final providers = await repository.loadProviders(
        CliTool.claude,
        importCredentialsFromGlobal: true,
      );
      expect(providers.single.hasClaudeCredentialsReady, isTrue);
      expect(
        fs.symlinks[fs.pathContext.join(
          base,
          'providers',
          'claude',
          'default',
          '.credentials.json',
        )],
        fs.pathContext.join(home, '.claude', '.credentials.json'),
      );
    },
  );

  test('load does not overwrite isolated provider credentials from global', () async {
    const home = '/home/user';
    AppStorage.installForTesting(
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
            'config': {
              'env': {},
              credentialBindingConfigKey: 'isolated',
            },
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

    await repository.loadProviders(CliTool.claude);

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
