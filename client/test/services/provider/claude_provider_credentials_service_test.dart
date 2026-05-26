import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/claude_credential_link_result.dart';
import 'package:teampilot/services/provider/claude_provider_credentials_service.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  late InMemoryFilesystem fs;
  late ClaudeProviderCredentialsService service;
  const base = '/data/tp';

  setUp(() {
    fs = InMemoryFilesystem();
    service = ClaudeProviderCredentialsService(fs: fs, basePath: base);
  });

  test('probe missing when no file', () async {
    final probe = await service.probe('work');
    expect(probe.isReady, isFalse);
    expect(
      probe.credentialPath,
      fs.pathContext.join(base, 'providers', 'claude', 'work', '.credentials.json'),
    );
  });

  test('probe ready when provider dir has credentials', () async {
    final path = fs.pathContext.join(
      base,
      'providers',
      'claude',
      'personal',
      '.credentials.json',
    );
    await fs.writeString(path, '{"claudeAiOauth":{"accessToken":"x"}}');
    final probe = await service.probe('personal');
    expect(probe.isReady, isTrue);
  });

  test('work and personal credentials are independent', () async {
    await fs.writeString(
      fs.pathContext.join(base, 'providers', 'claude', 'work', '.credentials.json'),
      '{"claudeAiOauth":{"accessToken":"work"}}',
    );
    expect((await service.probe('work')).isReady, isTrue);
    expect((await service.probe('personal')).isReady, isFalse);
  });

  test('importFromGlobal copies home credentials to provider dir', () async {
    const home = '/home/user';
    await fs.writeString(
      fs.pathContext.join(home, '.claude', '.credentials.json'),
      '{"claudeAiOauth":{"accessToken":"global"}}',
    );
    final ok = await service.importFromGlobal(
      'work',
      homeDirectory: home,
    );
    expect(ok, isTrue);
    expect((await service.probe('work')).isReady, isTrue);
  });

  test('importFromFile copies external file to provider dir', () async {
    await fs.writeString(
      '/ext/creds.json',
      '{"claudeAiOauth":{"accessToken":"file"}}',
    );
    final ok = await service.importFromFile('work', '/ext/creds.json');
    expect(ok, isTrue);
    expect((await service.probe('work')).isReady, isTrue);
  });

  test('import replace overwrites existing credentials', () async {
    await fs.writeString(
      fs.pathContext.join(base, 'providers', 'claude', 'work', '.credentials.json'),
      '{"claudeAiOauth":{"accessToken":"old"}}',
    );
    await fs.writeString(
      '/ext/new.json',
      '{"claudeAiOauth":{"accessToken":"new"}}',
    );
    expect(
      await service.importFromFile('work', '/ext/new.json', replace: true),
      isTrue,
    );
    final bytes = await fs.readBytes(
      fs.pathContext.join(base, 'providers', 'claude', 'work', '.credentials.json'),
    );
    expect(bytes, isNotNull);
    expect(String.fromCharCodes(bytes!), contains('new'));
  });

  test('ensureLinked symlinks session credentials from provider', () async {
    await fs.writeString(
      fs.pathContext.join(base, 'providers', 'claude', 'work', '.credentials.json'),
      '{"claudeAiOauth":{"accessToken":"work"}}',
    );
    const sessionDir = '/data/tp/config-profiles/teams/t1/members/s1/claude';
    final result = await service.ensureLinked(sessionDir, 'work');
    expect(result, CredentialLinkResult.linked);
    expect(
      fs.symlinks.containsKey(
        fs.pathContext.join(sessionDir, '.credentials.json'),
      ),
      isTrue,
    );
  });

  test('ensureLinked returns alreadyPresent when session has cred', () async {
    await fs.writeString(
      fs.pathContext.join(base, 'providers', 'claude', 'work', '.credentials.json'),
      '{"claudeAiOauth":{"accessToken":"work"}}',
    );
    const sessionDir = '/data/tp/config-profiles/teams/t1/members/s1/claude';
    await fs.writeString(
      fs.pathContext.join(sessionDir, '.credentials.json'),
      '{"claudeAiOauth":{"accessToken":"existing"}}',
    );
    final result = await service.ensureLinked(sessionDir, 'work');
    expect(result, CredentialLinkResult.alreadyPresent);
  });

  test('ensureLinked returns missing when provider has no cred', () async {
    const sessionDir = '/data/tp/config-profiles/teams/t1/members/s1/claude';
    final result = await service.ensureLinked(sessionDir, 'work');
    expect(result, CredentialLinkResult.missing);
  });
}
