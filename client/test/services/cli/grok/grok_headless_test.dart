import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/models/credential_lease.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/grok/capabilities/headless.dart';
import 'package:teampilot/services/cli/grok/grok_constants.dart';
import 'package:teampilot/services/cli/registry/capabilities/headless_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/launch/cli_launch_arg_assembler.dart';
import 'package:teampilot/services/provider/oauth_credential_authority.dart';
import 'package:teampilot/services/storage/home_storage.dart';
import 'package:toml/toml.dart';

import '../../../support/in_memory_filesystem.dart';

const _configDir = '/runtime/grok';

String _authJson({
  String key = 'provider',
  String refreshToken = 'rt',
  String expiresAt = '2026-11-14T11:30:00Z',
}) => jsonEncode({
  'https://auth.x.ai::b1a00492-073a-47ea-816f-4c329264a828': {
    'key': key,
    'refresh_token': refreshToken,
    'expires_at': expiresAt,
    'auth_mode': 'Oidc',
  },
});

final class _TestRefresher implements CredentialRefresher {
  @override
  Future<CredentialRefreshOutcome> refresh(String refreshToken) async =>
      RefreshSucceeded(
        accessToken: 'refreshed',
        refreshToken: 'rt-next',
        expiresAt: DateTime.utc(2026, 11, 14, 11, 30, 0),
      );
}

final class _TransientRefresher implements CredentialRefresher {
  @override
  Future<CredentialRefreshOutcome> refresh(String refreshToken) async =>
      throw const CredentialTransientException('SECRET_INTERNAL');
}

HeadlessLaunchContext _run({
  String prompt = 'P',
  String model = '',
  String effort = '',
  bool stream = false,
  bool expectJson = false,
  LaunchSecurityPolicy securityPolicy = LaunchSecurityPolicy.fullAccess,
}) => HeadlessLaunchContext(
  prompt: prompt,
  model: model,
  effort: effort,
  configDir: _configDir,
  stream: stream,
  expectJson: expectJson,
  securityPolicy: securityPolicy,
);

List<String> _assemble(HeadlessLaunchContext ctx) =>
    const CliLaunchArgAssembler().assembleHeadless(
      CliToolRegistry.builtIn().tryGet(CliTool.grok)!,
      ctx,
    );

void main() {
  group('capability shape', () {
    test('headless is supported and pins GROK_HOME', () {
      const cap = GrokHeadlessCapability();
      expect(cap.isSupported, isTrue);
      expect(cap.executable, 'grok');
      expect(cap.supportsStreaming, isTrue);
      expect(cap.supportsPromptStdin, isFalse);
      expect(cap.configFiles(_run()), isEmpty);
      expect(cap.buildEnvironment(_run()), {
        GrokConstants.homeEnvKey: _configDir,
        'GROK_DISABLE_AUTOUPDATER': '1',
      });
    });
  });

  group('result parsing', () {
    const cap = GrokHeadlessCapability();

    test('unwraps the single json object text field', () {
      expect(
        cap.extractText(
          ProcessResult(0, 0, '{"text":"  Hi  ","stopReason":"end_turn"}', ''),
        ),
        'Hi',
      );
    });

    test('joins streaming text events when end carries no text', () {
      const raw =
          '{"type":"thought","data":"hmm"}\n'
          '{"type":"text","data":"Hel"}\n'
          '{"type":"text","data":"lo"}\n'
          '{"type":"end","stopReason":"end_turn"}\n';
      expect(cap.extractText(ProcessResult(0, 0, raw, '')), 'Hello');
    });

    test('falls back to plain stdout and empty output', () {
      expect(cap.extractText(ProcessResult(0, 0, ' plain ', '')), 'plain');
      expect(cap.extractText(ProcessResult(0, 0, '   ', '')), '');
    });
  });

  group('launch args', () {
    test('full access passes model, always-approve and the prompt', () {
      final args = _assemble(_run(model: 'grok-4.6'));
      expect(args, containsAllInOrder(['--model', 'grok-4.6']));
      expect(args, contains('--always-approve'));
      expect(args, containsAllInOrder(['-p', 'P']));
      expect(args, isNot(contains('--permission-mode')));
    });

    test('requesting json selects the json output format', () {
      final args = _assemble(_run(model: 'grok-4.6', expectJson: true));
      expect(args, containsAllInOrder(['--output-format', 'json']));
    });

    test('streaming selects streaming-json', () {
      final args = _assemble(_run(model: 'grok-4.6', stream: true));
      expect(args, containsAllInOrder(['--output-format', 'streaming-json']));
    });

    test('effort and resume are forwarded', () {
      final args = const GrokHeadlessCapability()
          .buildHeadlessLaunchArgs(_run(effort: 'high', model: 'grok-4.6'))
          .expand((contribution) => contribution.args)
          .toList();
      expect(args, containsAllInOrder(['--reasoning-effort', 'high']));
    });

    test('ask policy falls back to the default permission mode', () {
      final args = const GrokHeadlessCapability()
          .buildHeadlessLaunchArgs(
            _run(securityPolicy: LaunchSecurityPolicy.ask),
          )
          .expand((contribution) => contribution.args)
          .toList();
      expect(args, containsAllInOrder(['--permission-mode', 'default']));
      expect(args, isNot(contains('--always-approve')));
    });
  });

  group('provisioning', () {
    late InMemoryFilesystem fs;
    late HomeStorage storage;
    late OAuthCredentialAuthority authority;
    late GrokHeadlessCapability cap;

    setUp(() {
      fs = InMemoryFilesystem();
      storage = fakeHomeStorage(filesystem: fs);
      authority = OAuthCredentialAuthority(
        fs: fs,
        basePath: '/tp',
        cliNamespace: 'grok',
        refresher: _TestRefresher(),
        now: () => DateTime.utc(2026, 11, 14, 11, 0, 0),
      );
      cap = GrokHeadlessCapability(storage: storage, authority: authority);
    });

    Future<void> seedAuthority() => authority.importFromLogin(
      'xai',
      utf8.encode(_authJson()),
    );

    HeadlessProvisionContext provisionCtx({
      String providerId = 'xai',
      AppProviderConfig? provider,
      String model = '',
    }) => HeadlessProvisionContext(
      provider: provider,
      providerId: providerId,
      model: model,
      effort: '',
      configDir: _configDir,
    );

    Future<Map<String, Object?>> readConfig() async => TomlDocument.parse(
      (await fs.readString('$_configDir/config.toml'))!,
    ).toMap();

    Future<Map<String, Object?>> readSessionScope() async {
      final raw = await fs.readString('$_configDir/auth.json');
      expect(raw, isNotNull);
      final auth = jsonDecode(raw!) as Map<String, Object?>;
      return auth.values.single as Map<String, Object?>;
    }

    test('writes the default model and an access-token-only auth.json',
        () async {
      await seedAuthority();
      const provider = AppProviderConfig(
        id: 'xai',
        cli: CliTool.grok,
        name: 'xAI',
        isOfficial: true,
        defaultModel: 'grok-4.6',
      );
      await fs.ensureDir(_configDir);
      await fs.atomicWrite(
        '$_configDir/config.toml',
        '[telemetry]\nenabled = false\n',
      );

      final result = await cap.provision(
        provisionCtx(provider: provider, model: 'grok-4.5'),
      );

      expect(result.credentialsReady, isTrue);
      expect(result.warnings, isEmpty);
      expect(result.extraEnvironment, isEmpty);
      final config = await readConfig();
      expect((config['models'] as Map)['default'], 'grok-4.5');
      expect((config['telemetry'] as Map)['enabled'], isFalse);
      final compat = config['compat'] as Map;
      expect((compat['claude'] as Map)['mcps'], isFalse);
      expect((compat['cursor'] as Map)['hooks'], isFalse);

      final scope = await readSessionScope();
      expect(scope['key'], 'provider');
      expect(scope['auth_mode'], 'Oidc');
      // The refresh token must never cross to the per-run home.
      expect(scope, isNot(contains('refresh_token')));
      expect(
        await fs.readString('$_configDir/auth.json'),
        isNot(contains('refresh_token')),
      );
    });

    test('migrates the pre-Authority provider auth.json on the first run',
        () async {
      await fs.ensureDir('/tp/providers/grok/xai');
      await fs.atomicWrite('/tp/providers/grok/xai/auth.json', _authJson());

      final result = await cap.provision(provisionCtx());

      expect(result.credentialsReady, isTrue);
      expect(result.warnings, isEmpty);
      expect((await readSessionScope())['key'], 'provider');
      expect(
        await fs.readString('/tp/providers/grok/xai/auth.json'),
        isNull,
        reason: 'migration must delete the legacy RT copy',
      );
    });

    test('an API key becomes XAI_API_KEY and skips auth.json', () async {
      const provider = AppProviderConfig(
        id: 'xai',
        cli: CliTool.grok,
        name: 'xAI',
        isOfficial: true,
        defaultModel: 'grok-4.6',
        apiKey: 'xai-key',
      );

      final result = await cap.provision(provisionCtx(provider: provider));

      expect(result.credentialsReady, isTrue);
      expect(result.extraEnvironment, {'XAI_API_KEY': 'xai-key'});
      expect((await fs.stat('$_configDir/auth.json')).exists, isFalse);
      expect((await readConfig())['models'], {'default': 'grok-4.6'});
    });

    test('missing auth without an API key is not ready', () async {
      final result = await cap.provision(provisionCtx());

      expect(result.credentialsReady, isFalse);
      expect(result.warnings, contains('grok_credentials_missing'));
      expect(result.extraEnvironment, isEmpty);
      expect((await fs.stat('$_configDir/auth.json')).exists, isFalse);
    });
  });

  test('no provider row still provisions from the authority credential',
      () async {
    final fs = InMemoryFilesystem();
    final storage = fakeHomeStorage(filesystem: fs);
    final authority = OAuthCredentialAuthority(
      fs: fs,
      basePath: '/tp',
      cliNamespace: 'grok',
      refresher: _TestRefresher(),
      now: () => DateTime.utc(2026, 11, 14, 11, 0, 0),
    );
    // The provider UI's importGlobal action moves ~/.grok/auth.json into the
    // Authority; headless no longer reads the machine home directly.
    await authority.importFromLogin('xai', utf8.encode(_authJson()));
    final cap = GrokHeadlessCapability(storage: storage, authority: authority);

    final result = await cap.provision(
      const HeadlessProvisionContext(
        provider: null,
        providerId: 'xai',
        model: '',
        effort: '',
        configDir: _configDir,
      ),
    );

    expect(result.credentialsReady, isTrue);
    final auth = jsonDecode((await fs.readString('$_configDir/auth.json'))!)
        as Map<String, Object?>;
    final scope = auth.values.single as Map<String, Object?>;
    expect(scope['key'], 'provider');
    expect(scope, isNot(contains('refresh_token')));
  });

  test('a transient refresh failure is not ready and does not leak the cause',
      () async {
    final fs = InMemoryFilesystem();
    final storage = fakeHomeStorage(filesystem: fs);
    final authority = OAuthCredentialAuthority(
      fs: fs,
      basePath: '/tp',
      cliNamespace: 'grok',
      refresher: _TransientRefresher(),
      now: () => DateTime.utc(2026, 11, 14, 11, 0, 0),
    );
    // Expired access token forces a refresh, which fails transiently.
    await authority.importFromLogin(
      'xai',
      utf8.encode(_authJson(expiresAt: '2026-11-14T10:00:00Z')),
    );
    final cap = GrokHeadlessCapability(storage: storage, authority: authority);

    final result = await cap.provision(
      const HeadlessProvisionContext(
        provider: null,
        providerId: 'xai',
        model: '',
        effort: '',
        configDir: _configDir,
      ),
    );

    expect(result.credentialsReady, isFalse);
    expect(result.warnings, isNotEmpty);
    // The raw internal cause must never reach the result / UI.
    expect(result.warnings.join(' '), isNot(contains('SECRET_INTERNAL')));
    expect(result.warnings.join(' '), isNot(contains('CredentialTransient')));
  });
}
