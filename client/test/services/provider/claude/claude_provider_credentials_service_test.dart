import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/credential_link_result.dart';
import 'package:teampilot/services/cli/cli_invocation.dart';
import 'package:teampilot/services/host/host_one_shot_runner.dart';
import 'package:teampilot/services/host/host_process_starter.dart';
import 'package:teampilot/services/host/process_run_handle.dart';
import 'package:teampilot/services/cli/claude/provider/claude_provider_credentials_service.dart';
import 'package:teampilot/services/provider/credential_binding.dart';
import 'package:teampilot/services/provider/credential_host_request.dart';
import 'package:teampilot/services/provider/provider_credential_host_runner.dart';

import '../../../support/in_memory_filesystem.dart';

class _ExitZeroHandle implements ProcessRunHandle {
  @override
  Future<int> get exitCode => Future.value(0);

  @override
  Stream<List<int>> get stdout => const Stream.empty();

  @override
  Stream<List<int>> get stderr => const Stream.empty();

  @override
  void kill() {}
}

class _CapturingStreamingStarter implements HostProcessStarter {
  _CapturingStreamingStarter(this.onStart);

  final void Function(HostRunRequest request) onStart;

  @override
  Future<ProcessRunHandle> start(HostRunRequest request) async {
    onStart(request);
    return _ExitZeroHandle();
  }
}

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
      fs.pathContext.join(
        base,
        'providers',
        'claude',
        'work',
        '.credentials.json',
      ),
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

  test('probe missing when oauth tokens are empty stubs', () async {
    final global = fs.pathContext.join(home, '.claude', '.credentials.json');
    await fs.writeString(
      global,
      jsonEncode({
        'claudeAiOauth': {
          'accessToken': '',
          'refreshToken': '',
          'expiresAt': 0,
          'scopes': ['user:inference'],
          'subscriptionType': 'pro',
        },
      }),
    );

    final probe = await service.probe(
      'work',
      binding: CredentialBindingKind.linked,
      homeDirectory: home,
    );
    expect(probe.isReady, isFalse);
  });

  test('ensureLinked returns missing for empty oauth stub', () async {
    final global = fs.pathContext.join(home, '.claude', '.credentials.json');
    await fs.writeString(
      global,
      '{"claudeAiOauth":{"accessToken":"","refreshToken":"","expiresAt":0}}',
    );
    await fs.createSymlink(
      target: global,
      linkPath: fs.pathContext.join(
        base,
        'providers',
        'claude',
        'claude-official',
        '.credentials.json',
      ),
    );

    final result = await service.ensureLinked(
      '/tmp/session-claude',
      'claude-official',
      binding: CredentialBindingKind.linked,
      homeDirectory: home,
    );
    expect(result, CredentialLinkResult.missing);
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
      fs.pathContext.join(
        base,
        'providers',
        'claude',
        'work',
        '.credentials.json',
      ),
      '{"claudeAiOauth":{"accessToken":"work"}}',
    );
    expect(
      (await service.probe(
        'work',
        binding: CredentialBindingKind.isolated,
      )).isReady,
      isTrue,
    );
    expect(
      (await service.probe(
        'personal',
        binding: CredentialBindingKind.isolated,
      )).isReady,
      isFalse,
    );
  });

  test(
    'importFromGlobal links provider credential to global home by default',
    () async {
      final global = fs.pathContext.join(home, '.claude', '.credentials.json');
      await fs.writeString(
        global,
        '{"claudeAiOauth":{"accessToken":"global"}}',
      );
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
    },
  );

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
      (await service.probe(
        'work',
        binding: CredentialBindingKind.isolated,
      )).isReady,
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
      (await service.probe(
        'work',
        binding: CredentialBindingKind.isolated,
      )).isReady,
      isTrue,
    );
  });

  test('import replace overwrites existing credentials', () async {
    await fs.writeString(
      fs.pathContext.join(
        base,
        'providers',
        'claude',
        'work',
        '.credentials.json',
      ),
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
      fs.pathContext.join(
        base,
        'providers',
        'claude',
        'work',
        '.credentials.json',
      ),
    );
    expect(bytes, isNotNull);
    expect(String.fromCharCodes(bytes!), contains('new'));
  });

  test('ensureLinked symlinks session credentials from provider', () async {
    await fs.writeString(
      fs.pathContext.join(
        base,
        'providers',
        'claude',
        'work',
        '.credentials.json',
      ),
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

  test(
    'ensureLinked linked mode symlinks session to global credential',
    () async {
      final global = fs.pathContext.join(home, '.claude', '.credentials.json');
      await fs.writeString(
        global,
        '{"claudeAiOauth":{"accessToken":"global"}}',
      );
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
    },
  );

  test('ensureLinked returns alreadyPresent when session has cred', () async {
    await fs.writeString(
      fs.pathContext.join(
        base,
        'providers',
        'claude',
        'work',
        '.credentials.json',
      ),
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
    HostRunRequest? capturedRequest;
    const preferencePath = 'wsl.exe /home/user/.local/bin/claude';

    final wslService = ClaudeProviderCredentialsService(
      fs: fs,
      basePath: base,
      resolveClaudeExecutable: () => preferencePath,
      resolveHomeDirectory: () => home,
      hostRunner: ProviderCredentialHostRunner(
        oneShot: () => throw StateError('one-shot should not be called for login'),
        streaming: () => _CapturingStreamingStarter((request) {
          capturedRequest = request;
        }),
      ),
    );

    final loginResult = await wslService.runAuthLogin(
      'work',
      binding: CredentialBindingKind.linked,
      homeDirectory: home,
    );
    expect(loginResult.ok, isFalse);
    expect(capturedRequest, isNotNull);
    expect(capturedRequest!.arguments, containsAll(const ['auth', 'login']));
    // Native Windows keeps wsl.exe; WSL/SSH home unwraps to the Linux binary.
    expect(
      capturedRequest!.executable,
      CredentialHostRequest.hostExecutable(preferencePath),
    );
    expect(
      capturedRequest!.arguments,
      contains('/home/user/.local/bin/claude'),
    );
    expect(capturedRequest!.environment!['CLAUDE_CONFIG_DIR'], '$home/.claude');
    expect(capturedRequest!.environment!['CCGUI_CLI_LOGIN_AUTHORIZED'], '1');
  });

  test('runAuthLogin uses provider dir when isolated', () async {
    HostRunRequest? capturedRequest;

    final nativeService = ClaudeProviderCredentialsService(
      fs: fs,
      basePath: base,
      hostRunner: ProviderCredentialHostRunner(
        oneShot: () => throw StateError('one-shot should not be called for login'),
        streaming: () => _CapturingStreamingStarter((request) {
          capturedRequest = request;
        }),
      ),
    );

    await nativeService.runAuthLogin(
      'work',
      binding: CredentialBindingKind.isolated,
    );
    expect(
      capturedRequest!.environment!['CLAUDE_CONFIG_DIR'],
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
