import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/claude_credential_link_result.dart';
import 'package:teampilot/services/cli/cli_invocation.dart';
import 'package:teampilot/services/provider/claude/claude_provider_credentials_service.dart';
import 'package:teampilot/services/provider/credential_binding.dart';

import '../../../support/in_memory_filesystem.dart';

void main() {
  late InMemoryFilesystem fs;
  late ClaudeProviderCredentialsService service;
  const base = '/data/tp';
  const home = '/home/user';

  setUp(() {
    fs = InMemoryFilesystem();
    service = ClaudeProviderCredentialsService(
      fs: fs,
      basePath: base,
      resolveHomeDirectory: () => home,
    );
  });

  test('probe missing when no file', () async {
    final probe = await service.probe(
      'work',
      binding: CredentialBindingKind.isolated,
    );
    expect(probe.isReady, isFalse);
    expect(
      probe.credentialPath,
      fs.pathContext.join(base, 'providers', 'claude', 'work', '.credentials.json'),
    );
  });

  test('linked probe reads global credential path', () async {
    final global = fs.pathContext.join(home, '.claude', '.credentials.json');
    await fs.writeString(global, '{"claudeAiOauth":{"accessToken":"global"}}');

    final probe = await service.probe(
      'work',
      binding: CredentialBindingKind.linked,
      homeDirectory: home,
    );
    expect(probe.isReady, isTrue);
    expect(probe.credentialPath, global);
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
    final probe = await service.probe(
      'personal',
      binding: CredentialBindingKind.isolated,
    );
    expect(probe.isReady, isTrue);
  });

  test('work and personal credentials are independent', () async {
    await fs.writeString(
      fs.pathContext.join(base, 'providers', 'claude', 'work', '.credentials.json'),
      '{"claudeAiOauth":{"accessToken":"work"}}',
    );
    expect(
      (await service.probe('work', binding: CredentialBindingKind.isolated)).isReady,
      isTrue,
    );
    expect(
      (await service.probe('personal', binding: CredentialBindingKind.isolated)).isReady,
      isFalse,
    );
  });

  test('importFromGlobal links provider credential to global home by default', () async {
    final global = fs.pathContext.join(home, '.claude', '.credentials.json');
    await fs.writeString(global, '{"claudeAiOauth":{"accessToken":"global"}}');
    final result = await service.importFromGlobal(
      'work',
      homeDirectory: home,
    );
    expect(result.ok, isTrue);
    final providerCred = fs.pathContext.join(
      base,
      'providers',
      'claude',
      'work',
      '.credentials.json',
    );
    expect(fs.symlinks[providerCred], global);
    expect(
      (await service.probe(
        'work',
        binding: CredentialBindingKind.linked,
        homeDirectory: home,
      )).isReady,
      isTrue,
    );
  });

  test('importFromGlobal isolated copies bytes to provider dir', () async {
    await fs.writeString(
      fs.pathContext.join(home, '.claude', '.credentials.json'),
      '{"claudeAiOauth":{"accessToken":"global"}}',
    );
    final result = await service.importFromGlobal(
      'work',
      homeDirectory: home,
      binding: CredentialBindingKind.isolated,
    );
    expect(result.ok, isTrue);
    expect(fs.symlinks, isEmpty);
    expect(
      (await service.probe('work', binding: CredentialBindingKind.isolated)).isReady,
      isTrue,
    );
  });

  test('importFromFile copies external file to provider dir', () async {
    await fs.writeString(
      '/ext/creds.json',
      '{"claudeAiOauth":{"accessToken":"file"}}',
    );
    final result = await service.importFromFile('work', '/ext/creds.json');
    expect(result.ok, isTrue);
    expect(
      (await service.probe('work', binding: CredentialBindingKind.isolated)).isReady,
      isTrue,
    );
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
      (await service.importFromFile('work', '/ext/new.json', replace: true)).ok,
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
    const sessionDir = '/data/tp/identities-runtime/t1/members/s1/claude';
    final result = await service.ensureLinked(
      sessionDir,
      'work',
      binding: CredentialBindingKind.isolated,
    );
    expect(result, CredentialLinkResult.linked);
    expect(
      fs.symlinks.containsKey(
        fs.pathContext.join(sessionDir, '.credentials.json'),
      ),
      isTrue,
    );
  });

  test('ensureLinked linked mode symlinks session to global credential', () async {
    final global = fs.pathContext.join(home, '.claude', '.credentials.json');
    await fs.writeString(global, '{"claudeAiOauth":{"accessToken":"global"}}');
    const sessionDir = '/data/tp/identities-runtime/t1/members/s1/claude';
    final result = await service.ensureLinked(
      sessionDir,
      'work',
      binding: CredentialBindingKind.linked,
      homeDirectory: home,
    );
    expect(result, CredentialLinkResult.linked);
    expect(
      fs.symlinks[fs.pathContext.join(sessionDir, '.credentials.json')],
      global,
    );
  });

  test('ensureLinked returns alreadyPresent when session has cred', () async {
    await fs.writeString(
      fs.pathContext.join(base, 'providers', 'claude', 'work', '.credentials.json'),
      '{"claudeAiOauth":{"accessToken":"work"}}',
    );
    const sessionDir = '/data/tp/identities-runtime/t1/members/s1/claude';
    await fs.writeString(
      fs.pathContext.join(sessionDir, '.credentials.json'),
      '{"claudeAiOauth":{"accessToken":"existing"}}',
    );
    final result = await service.ensureLinked(
      sessionDir,
      'work',
      binding: CredentialBindingKind.isolated,
    );
    expect(result, CredentialLinkResult.alreadyPresent);
  });

  test('ensureLinked returns missing when provider has no cred', () async {
    const sessionDir = '/data/tp/identities-runtime/t1/members/s1/claude';
    final result = await service.ensureLinked(
      sessionDir,
      'work',
      binding: CredentialBindingKind.isolated,
    );
    expect(result, CredentialLinkResult.missing);
  });

  test('runAuthLogin uses global config dir when linked', () async {
    String? capturedExecutable;
    List<String>? capturedArgs;
    Map<String, String>? capturedEnv;

    final wslService = ClaudeProviderCredentialsService(
      fs: fs,
      basePath: base,
      resolveClaudeExecutable: () => 'wsl.exe /home/user/.local/bin/claude',
      resolveHomeDirectory: () => home,
      processRunner: (executable, arguments, {environment}) async {
        capturedExecutable = executable;
        capturedArgs = arguments;
        capturedEnv = environment;
        return ProcessResult(0, 0, '', '');
      },
    );

    final invocation = CliInvocation.fromExecutable(
      'wsl.exe /home/user/.local/bin/claude',
    );

    final loginResult = await wslService.runAuthLogin(
      'work',
      binding: CredentialBindingKind.linked,
      homeDirectory: home,
    );
    expect(loginResult.ok, isFalse);
    expect(capturedExecutable, 'wsl.exe');
    expect(capturedArgs, isNotNull);
    expect(capturedArgs, containsAll(const ['auth', 'login']));
    expect(capturedArgs, contains('/home/user/.local/bin/claude'));

    if (invocation.usesWsl) {
      expect(capturedArgs!.first, 'env');
      expect(
        capturedArgs,
        contains('CLAUDE_CONFIG_DIR=/home/user/.claude'),
      );
      expect(capturedArgs, contains('CCGUI_CLI_LOGIN_AUTHORIZED=1'));
      expect(capturedEnv, isNull);
    } else {
      expect(capturedArgs!.first, '/home/user/.local/bin/claude');
      expect(capturedEnv, isNotNull);
      expect(capturedEnv!['CLAUDE_CONFIG_DIR'], '$home/.claude');
      expect(capturedEnv!['CCGUI_CLI_LOGIN_AUTHORIZED'], '1');
    }
  });

  test('runAuthLogin uses provider dir when isolated', () async {
    Map<String, String>? capturedEnv;

    final nativeService = ClaudeProviderCredentialsService(
      fs: fs,
      basePath: base,
      processRunner: (executable, arguments, {environment}) async {
        capturedEnv = environment;
        return ProcessResult(0, 0, '', '');
      },
    );

    await nativeService.runAuthLogin(
      'work',
      binding: CredentialBindingKind.isolated,
    );
    expect(
      capturedEnv!['CLAUDE_CONFIG_DIR'],
      fs.pathContext.join(base, 'providers', 'claude', 'work'),
    );
  });

  test('resolveProcessLaunch keeps native spawn plan for bare claude', () {
    final launch = CliInvocation.resolveProcessLaunch(
      executable: 'claude',
      subcommand: const ['auth', 'login'],
      environment: const {'CLAUDE_CONFIG_DIR': '/cfg'},
    );
    expect(launch.executable, 'claude');
    expect(launch.arguments, const ['auth', 'login']);
    expect(launch.environment, const {'CLAUDE_CONFIG_DIR': '/cfg'});
  });
}
