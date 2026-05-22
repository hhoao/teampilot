import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/repositories/app_provider_repository.dart';
import 'package:teampilot/services/claude_provider_credentials_service.dart';

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
}
