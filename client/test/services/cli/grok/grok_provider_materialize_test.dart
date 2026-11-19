import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/models/credential_lease.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/agent_status/member_agent_status_endpoint.dart';
import 'package:teampilot/services/chat/launch/config_profile_service.dart';
import 'package:teampilot/services/chat/launch/staging/manifest/launch_manifest.dart';
import 'package:teampilot/services/chat/launch/staging/manifest/manifest_filesystem.dart';
import 'package:teampilot/services/cli/grok/capabilities/acp.dart';
import 'package:teampilot/services/cli/grok/capabilities/provider.dart';
import 'package:teampilot/services/cli/grok/grok_constants.dart';
import 'package:teampilot/services/cli/grok/provider/grok_credential_adapter.dart';
import 'package:teampilot/services/cli/registry/capabilities/provider_capability.dart';
import 'package:teampilot/services/provider/credential_lease_endpoint.dart';
import 'package:teampilot/services/provider/oauth_credential_authority.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';
import 'package:toml/toml.dart';

import '../../../support/in_memory_filesystem.dart';

Map<String, Object?> _providerRow({
  String id = 'xai',
  String? apiKey,
  String defaultModel = 'grok-4.6',
}) => {
  'id': id,
  'cli': 'grok',
  'name': 'xAI',
  'isOfficial': true,
  'defaultModel': defaultModel,
  if (apiKey != null) 'apiKey': apiKey,
};

final class _TestRefresher implements CredentialRefresher {
  @override
  Future<CredentialRefreshOutcome> refresh(String refreshToken) async =>
      RefreshSucceeded(
        accessToken: 'provider',
        refreshToken: 'rt',
        expiresAt: DateTime.utc(2026, 11, 14, 11, 30, 0),
      );
}

final class _RejectingRefresher implements CredentialRefresher {
  @override
  Future<CredentialRefreshOutcome> refresh(String refreshToken) async =>
      const RefreshRejected();
}

/// Throws a transient whose cause deliberately contains internal text that
/// must never reach the session-connect failure surfaced to the UI.
final class _TransientRefresher implements CredentialRefresher {
  @override
  Future<CredentialRefreshOutcome> refresh(String refreshToken) async =>
      throw const CredentialTransientException('SECRET_INTERNAL');
}

const _agentStatus = MemberAgentStatusEndpoint(
  url: 'http://127.0.0.1:35297/agent-status',
  sessionId: 'session-1',
);

Map<String, Object?> _authJsonPayload() => {
  'scope': {
    'key': 'provider',
    'refresh_token': 'rt',
    'expires_at': '2026-11-14T11:30:00Z',
  },
};

void main() {
  test(
    'writes models.default and materializes an auth provider command',
    () async {
      final fs = InMemoryFilesystem();
      final storage = fakeHomeStorage(filesystem: fs);
      final service = ConfigProfileService(
        basePath: '/tp',
        fs: fs,
        layout: RuntimeLayout(teampilotRoot: '/tp', fs: fs),
        storage: storage,
      );

      final authority = OAuthCredentialAuthority(
        fs: fs,
        basePath: '/tp',
        cliNamespace: 'grok',
        refresher: _TestRefresher(),
        now: () => DateTime.utc(2026, 11, 14, 11, 0, 0),
      );
      await authority.importFromLogin(
        'xai',
        utf8.encode(jsonEncode(_authJsonPayload())),
      );
      final adapter = GrokCredentialAdapter(
        authority: authority,
        sessionProviderId: (_) => 'xai',
        isWindows: false,
        now: () => DateTime.utc(2026, 11, 14, 11, 0, 0),
      );
      final capability = GrokProviderCapability(
        storage: storage,
        authority: authority,
        adapter: adapter,
      );

      const member = TeamMemberConfig(
        id: 'm1',
        name: 'Member',
        provider: 'xai',
        model: 'grok-4.5',
      );
      final scope = resolveLaunchProfileScope(
        workspaceId: 'workspace-1',
        teamId: 'team-a',
        appSessionId: 'session-1',
        cliTeamName: 'session-1',
      );

      final contribution = await capability.materializeSessionHome(
        sessionHomeContextFromLaunch(
          ConfigProfileLaunchContext(
            workspaceId: 'workspace-1',
            teamId: 'team-a',
            sessionId: scope.sessionId,
            scope: scope,
            member: member,
            members: const [member],
            workingDirectory: '/workspace/workspace',
            paths: service,
            catalog: service,
            agentStatus: _agentStatus,
          ),
          CliTool.grok,
        ),
      );

      final configDir = contribution.environment[GrokConstants.homeEnvKey]!;
      expect(contribution.environment, isNot(contains('XAI_API_KEY')));
      expect(contribution.warnings, isEmpty);
      expect(await fs.readString(p.posix.join(configDir, 'auth.json')), isNull);
      expect(
        contribution.environment[GrokConstants.authProviderCommandEnvKey],
        isNotNull,
      );
      final config = TomlDocument.parse(
        (await fs.readString(p.posix.join(configDir, 'config.toml')))!,
      ).toMap();
      expect((config['models'] as Map)['default'], 'grok-4.5');
      final compat = config['compat'] as Map;
      final claudeCompat = compat['claude'] as Map;
      expect(claudeCompat['mcps'], isFalse);
      expect(claudeCompat['hooks'], isFalse);
      expect(claudeCompat['rules'], isFalse);
      expect((compat['cursor'] as Map)['mcps'], isFalse);
      expect((compat['codex'] as Map)['sessions'], isFalse);
    },
  );

  test('simple session materializes the lease shim into the session tool dir '
      'ACP launches with', () async {
    final fs = InMemoryFilesystem();
    final storage = fakeHomeStorage(filesystem: fs);
    final service = ConfigProfileService(
      basePath: '/tp',
      fs: fs,
      layout: RuntimeLayout(teampilotRoot: '/tp', fs: fs),
      storage: storage,
    );

    final authority = OAuthCredentialAuthority(
      fs: fs,
      basePath: '/tp',
      cliNamespace: 'grok',
      refresher: _TestRefresher(),
      now: () => DateTime.utc(2026, 11, 14, 11, 0, 0),
    );
    await authority.importFromLogin(
      'xai',
      utf8.encode(jsonEncode(_authJsonPayload())),
    );
    final capability = GrokProviderCapability(
      storage: storage,
      authority: authority,
      adapter: GrokCredentialAdapter(
        authority: authority,
        sessionProviderId: (_) => 'xai',
        isWindows: false,
        now: () => DateTime.utc(2026, 11, 14, 11, 0, 0),
      ),
    );

    // Personal/Simple launches synthesize a member whose id is the session
    // id and leave scope.memberId empty; ACP launches with the non-member
    // session tool dir as GROK_HOME.
    const sessionId = 'session-1';
    const member = TeamMemberConfig(
      id: sessionId,
      name: sessionId,
      provider: 'xai',
      model: 'grok-4.5',
    );
    final scope = resolveLaunchProfileScope(
      workspaceId: 'workspace-1',
      teamId: 'workspace-1',
      appSessionId: sessionId,
      cliTeamName: sessionId,
    );

    final contribution = await capability.materializeSessionHome(
      sessionHomeContextFromLaunch(
        ConfigProfileLaunchContext(
          workspaceId: 'workspace-1',
          teamId: '',
          sessionId: sessionId,
          scope: scope,
          member: member,
          members: const [member],
          workingDirectory: '/workspace/workspace',
          paths: service,
          catalog: service,
          agentStatus: _agentStatus,
        ),
        CliTool.grok,
      ),
    );

    final expectedDir = service.sessionToolDir(
      'workspace-1',
      sessionId,
      CliTool.grok.value,
    );
    expect(
      contribution.environment[GrokConstants.homeEnvKey],
      expectedDir,
      reason: 'GROK_HOME must match the ACP launch session tool dir',
    );
    expect(
      (await fs.stat(
        p.posix.join(expectedDir, 'bin', GrokConstants.leaseShimFileName),
      )).isFile,
      isTrue,
      reason: 'the auth provider shim must land in the launched GROK_HOME',
    );
    expect(
      (await fs.stat(
        p.posix.join(expectedDir, GrokConstants.leaseConfigFileName),
      )).isFile,
      isTrue,
    );
    expect(await fs.readString(p.posix.join(expectedDir, 'auth.json')), isNull);
  });

  test('an API key is injected and stale session auth is removed', () async {
    final fs = InMemoryFilesystem();
    final storage = fakeHomeStorage(filesystem: fs);
    final service = ConfigProfileService(
      basePath: '/tp',
      fs: fs,
      layout: RuntimeLayout(teampilotRoot: '/tp', fs: fs),
      storage: storage,
    );
    final capability = GrokProviderCapability(storage: storage);

    await fs.ensureDir('/tp/providers/grok');
    await fs.atomicWrite(
      '/tp/providers/grok/providers.json',
      jsonEncode({
        'providers': {'xai': _providerRow(apiKey: 'xai-key')},
      }),
    );

    const member = TeamMemberConfig(id: 'm1', name: 'Member', provider: 'xai');
    final scope = resolveLaunchProfileScope(
      workspaceId: 'workspace-1',
      teamId: 'team-a',
      appSessionId: 'session-1',
      cliTeamName: 'session-1',
    );
    final context = sessionHomeContextFromLaunch(
      ConfigProfileLaunchContext(
        workspaceId: 'workspace-1',
        teamId: 'team-a',
        sessionId: scope.sessionId,
        scope: scope,
        member: member,
        members: const [member],
        workingDirectory: '/workspace/workspace',
        paths: service,
        catalog: service,
      ),
      CliTool.grok,
    );
    final configDir = service.sessionToolDir(
      'workspace-1',
      scope.sessionId,
      CliTool.grok.value,
    );
    await fs.ensureDir(configDir);
    await fs.atomicWrite(p.posix.join(configDir, 'auth.json'), 'stale');
    await fs.atomicWrite(
      p.posix.join(configDir, GrokConstants.authMarkerFileName),
      'stale',
    );

    final contribution = await capability.materializeSessionHome(context);

    expect(contribution.environment, {
      GrokConstants.homeEnvKey: configDir,
      GrokConstants.apiKeyEnvKey: 'xai-key',
    });
    expect(
      (await fs.stat(p.posix.join(configDir, 'auth.json'))).exists,
      isFalse,
    );
    expect(
      (await fs.stat(
        p.posix.join(configDir, GrokConstants.authMarkerFileName),
      )).exists,
      isFalse,
    );
  });

  test(
    'cross-machine stages the lease shim through the work-plane manifest',
    () async {
      final homeFs = InMemoryFilesystem();
      final storage = fakeHomeStorage(filesystem: homeFs, appDataRoot: '/tp');
      final catalogService = ConfigProfileService(
        basePath: '/tp',
        fs: homeFs,
        layout: RuntimeLayout(teampilotRoot: '/tp', fs: homeFs),
        storage: storage,
      );
      final manifest = LaunchManifest();
      final workFs = ManifestFilesystem(
        manifest: manifest,
        readDelegate: homeFs,
      );
      final workService = ConfigProfileService(
        basePath: '/remote/tp',
        fs: workFs,
        layout: RuntimeLayout(teampilotRoot: '/remote/tp', fs: workFs),
        storage: storage,
      );

      final authority = OAuthCredentialAuthority(
        fs: homeFs,
        basePath: '/tp',
        cliNamespace: 'grok',
        refresher: _TestRefresher(),
        now: () => DateTime.utc(2026, 11, 14, 11, 0, 0),
      );
      await authority.importFromLogin(
        'xai',
        utf8.encode(jsonEncode(_authJsonPayload())),
      );
      final capability = GrokProviderCapability(
        storage: storage,
        authority: authority,
        adapter: GrokCredentialAdapter(
          authority: authority,
          sessionProviderId: (_) => 'xai',
          isWindows: false,
          now: () => DateTime.utc(2026, 11, 14, 11, 0, 0),
        ),
      );

      const member = TeamMemberConfig(
        id: 'm1',
        name: 'Member',
        provider: 'xai',
      );
      final scope = resolveLaunchProfileScope(
        workspaceId: 'workspace-1',
        teamId: 'team-a',
        appSessionId: 'session-1',
        cliTeamName: 'session-1',
      );
      final contribution = await capability.materializeSessionHome(
        SessionHomeContext(
          workspaceId: 'workspace-1',
          teamId: 'team-a',
          sessionId: scope.sessionId,
          scope: scope,
          tool: CliTool.grok,
          paths: workService,
          catalog: catalogService,
          members: const [member],
          member: member,
          workingDirectory: '/workspace/workspace',
          crossMachine: true,
          agentStatus: const MemberAgentStatusEndpoint(
            url: 'http://127.0.0.1:35297/agent-status',
            token: 'remote-token',
            sessionId: 'session-1',
          ),
        ),
      );

      final configDir = contribution.environment[GrokConstants.homeEnvKey]!;
      expect(configDir, startsWith('/remote/tp/'));
      final writes = manifest.entries
          .whereType<ManifestWriteFile>()
          .map((entry) => entry.path)
          .toList();
      expect(
        writes,
        contains(
          p.posix.join(configDir, 'bin', GrokConstants.leaseShimFileName),
        ),
        reason: 'the remote seat must receive the auth provider shim',
      );
      expect(
        writes,
        contains(p.posix.join(configDir, GrokConstants.leaseConfigFileName)),
      );
      // The refresh token never crosses to the work plane: no auth.json copy.
      expect(manifest.entries.whereType<ManifestCopyFile>(), isEmpty);
      expect(
        await homeFs.readString(p.posix.join(configDir, 'auth.json')),
        isNull,
      );
      expect(
        homeFs.files.keys.where((k) => k.startsWith(configDir)),
        isEmpty,
        reason: 'cross-machine staging must not write through the home fs',
      );
      final leaseConfig = await workFs.readString(
        p.posix.join(configDir, GrokConstants.leaseConfigFileName),
      );
      expect(leaseConfig, contains('"providerId":"xai"'));
      expect(
        leaseConfig,
        contains(
          '"endpoint":"http://127.0.0.1:35297'
          '${CredentialLeaseEndpoint.path}"',
        ),
      );
    },
  );

  test('probe reflects Authority health instead of file size', () async {
    final fs = InMemoryFilesystem();
    final storage = fakeHomeStorage(filesystem: fs);
    final authority = OAuthCredentialAuthority(
      fs: fs,
      basePath: '/tp',
      cliNamespace: 'grok',
      refresher: _TestRefresher(),
      now: () => DateTime.utc(2026, 11, 14, 11, 0, 0),
    );
    await fs.ensureDir('/tp/providers/grok/xai');
    await fs.atomicWrite(
      '/tp/providers/grok/xai/auth.json',
      jsonEncode(_authJsonPayload()),
    );
    final capability = GrokProviderCapability(
      storage: storage,
      authority: authority,
      adapter: GrokCredentialAdapter(
        authority: authority,
        sessionProviderId: (_) => 'xai',
        isWindows: false,
        now: () => DateTime.utc(2026, 11, 14, 11, 0, 0),
      ),
    );

    // A non-empty legacy auth.json alone must NOT count as ready.
    final probe = await capability.probe(
      const AppProviderConfig(
        id: 'xai',
        cli: CliTool.grok,
        name: 'xAI',
        isOfficial: true,
        apiKey: '',
        apiKeyField: 'api_key',
        baseUrl: '',
        defaultModel: 'grok-4.7',
        createdAt: 0,
        updatedAt: 0,
      ),
    );
    expect(probe.isReady, isFalse);
  });

  test('probe is ready for an API-key row and for a ready lease', () async {
    final fs = InMemoryFilesystem();
    final storage = fakeHomeStorage(filesystem: fs);
    final authority = OAuthCredentialAuthority(
      fs: fs,
      basePath: '/tp',
      cliNamespace: 'grok',
      refresher: _TestRefresher(),
      now: () => DateTime.utc(2026, 11, 14, 11, 0, 0),
    );
    await authority.importFromLogin(
      'xai',
      utf8.encode(jsonEncode(_authJsonPayload())),
    );
    final capability = GrokProviderCapability(
      storage: storage,
      authority: authority,
    );

    const row = AppProviderConfig(
      id: 'xai',
      cli: CliTool.grok,
      name: 'xAI',
      isOfficial: true,
    );
    expect((await capability.probe(row)).isReady, isTrue);

    final apiKeyRow = const AppProviderConfig(
      id: 'xai',
      cli: CliTool.grok,
      name: 'xAI',
      isOfficial: true,
      apiKey: 'xai-key',
    );
    expect((await capability.probe(apiKeyRow)).isReady, isTrue);
  });


  test('an OAuth seat drops a stale session auth.json and injects the shim',
      () async {
    final fs = InMemoryFilesystem();
    final storage = fakeHomeStorage(filesystem: fs);
    final service = ConfigProfileService(
      basePath: '/tp',
      fs: fs,
      layout: RuntimeLayout(teampilotRoot: '/tp', fs: fs),
      storage: storage,
    );
    final authority = OAuthCredentialAuthority(
      fs: fs,
      basePath: '/tp',
      cliNamespace: 'grok',
      refresher: _TestRefresher(),
      now: () => DateTime.utc(2026, 11, 14, 11, 0, 0),
    );
    await authority.importFromLogin(
      'xai',
      utf8.encode(jsonEncode(_authJsonPayload())),
    );
    final capability = GrokProviderCapability(
      storage: storage,
      authority: authority,
      adapter: GrokCredentialAdapter(
        authority: authority,
        sessionProviderId: (_) => 'xai',
        isWindows: false,
        now: () => DateTime.utc(2026, 11, 14, 11, 0, 0),
      ),
    );

    const member = TeamMemberConfig(id: 'm1', name: 'Member', provider: 'xai');
    final scope = resolveLaunchProfileScope(
      workspaceId: 'workspace-1',
      teamId: 'team-a',
      appSessionId: 'session-1',
      cliTeamName: 'session-1',
    );
    final ctx = sessionHomeContextFromLaunch(
      ConfigProfileLaunchContext(
        workspaceId: 'workspace-1',
        teamId: 'team-a',
        sessionId: scope.sessionId,
        scope: scope,
        member: member,
        members: const [member],
        workingDirectory: '/workspace/workspace',
        paths: service,
        catalog: service,
        agentStatus: _agentStatus,
      ),
      CliTool.grok,
    );
    final configDir = service.sessionToolDir(
      'workspace-1',
      scope.sessionId,
      CliTool.grok.value,
    );
    await fs.ensureDir(configDir);
    await fs.atomicWrite(p.posix.join(configDir, 'auth.json'), 'stale');
    await fs.atomicWrite(
      p.posix.join(configDir, GrokConstants.authMarkerFileName),
      'stale',
    );

    final contribution = await capability.materializeSessionHome(ctx);

    expect(
      (await fs.stat(p.posix.join(configDir, 'auth.json'))).exists,
      isFalse,
      reason: 'an OAuth seat must not inherit a previous launch token',
    );
    expect(
      (await fs.stat(
        p.posix.join(configDir, GrokConstants.authMarkerFileName),
      )).exists,
      isFalse,
    );
    expect(
      contribution.environment[GrokConstants.authProviderCommandEnvKey],
      isNotNull,
    );
  });

  test('probe is ready while the access token is only expiring', () async {
    final fs = InMemoryFilesystem();
    final storage = fakeHomeStorage(filesystem: fs);
    final authority = OAuthCredentialAuthority(
      fs: fs,
      basePath: '/tp',
      cliNamespace: 'grok',
      refresher: _TestRefresher(),
      now: () => DateTime.utc(2026, 11, 14, 11, 0, 0),
    );
    // Access token already expired, RT still present: a lease can refresh it.
    await authority.importFromLogin(
      'xai',
      utf8.encode(
        jsonEncode({
          'scope': {
            'key': 'stale',
            'refresh_token': 'rt',
            'expires_at': '2026-11-14T10:00:00Z',
          },
        }),
      ),
    );
    expect(await authority.status('xai'), CredentialHealth.expiring);
    final capability = GrokProviderCapability(
      storage: storage,
      authority: authority,
    );

    const row = AppProviderConfig(
      id: 'xai',
      cli: CliTool.grok,
      name: 'xAI',
      isOfficial: true,
    );
    expect((await capability.probe(row)).isReady, isTrue);
  });

  test('probe reports missing after the IdP rejects the refresh token',
      () async {
    final fs = InMemoryFilesystem();
    final storage = fakeHomeStorage(filesystem: fs);
    final authority = OAuthCredentialAuthority(
      fs: fs,
      basePath: '/tp',
      cliNamespace: 'grok',
      refresher: _RejectingRefresher(),
      now: () => DateTime.utc(2026, 11, 14, 11, 0, 0),
    );
    await authority.importFromLogin(
      'xai',
      utf8.encode(
        jsonEncode({
          'scope': {
            'key': 'stale',
            'refresh_token': 'rt',
            'expires_at': '2026-11-14T10:00:00Z',
          },
        }),
      ),
    );
    await expectLater(
      authority.lease(providerId: 'xai', sessionId: 's1'),
      throwsA(isA<CredentialUnavailableException>()),
    );
    final capability = GrokProviderCapability(
      storage: storage,
      authority: authority,
    );

    const row = AppProviderConfig(
      id: 'xai',
      cli: CliTool.grok,
      name: 'xAI',
      isOfficial: true,
    );
    expect((await capability.probe(row)).isReady, isFalse);
  });

  group('credential actions', () {
    late InMemoryFilesystem fs;
    late OAuthCredentialAuthority authority;
    late GrokProviderCapability capability;

    setUp(() {
      fs = InMemoryFilesystem();
      final storage = fakeHomeStorage(filesystem: fs);
      authority = OAuthCredentialAuthority(
        fs: fs,
        basePath: '/tp',
        cliNamespace: 'grok',
        refresher: _TestRefresher(),
        now: () => DateTime.utc(2026, 11, 14, 11, 0, 0),
      );
      capability = GrokProviderCapability(
        storage: storage,
        authority: authority,
        adapter: GrokCredentialAdapter(
          authority: authority,
          sessionProviderId: (_) => 'xai',
          isWindows: false,
          now: () => DateTime.utc(2026, 11, 14, 11, 0, 0),
        ),
      );
    });

    Future<String> readCredential() async =>
        (await fs.readString('/tp/providers/grok/xai/credential.json')) ?? '';

    test('login imports the isolated auth.json into the Authority', () async {
      final loginPath = '/tp/cli-login/grok/xai/config/auth.json';
      await fs.ensureDir(p.posix.dirname(loginPath));
      await fs.atomicWrite(loginPath, jsonEncode(_authJsonPayload()));

      final result = await capability.execute(
        providerId: 'xai',
        kind: ProviderCredentialActionKind.login,
      );

      expect(result.ok, isTrue);
      expect(await readCredential(), contains('rt'));
      expect(await authority.status('xai'), CredentialHealth.ready);
    });

    test('login fails without a completed login auth.json', () async {
      final loginPath = '/tp/cli-login/grok/xai/config/auth.json';
      await fs.ensureDir(p.posix.dirname(loginPath));
      await fs.atomicWrite(loginPath, '');

      final result = await capability.execute(
        providerId: 'xai',
        kind: ProviderCredentialActionKind.login,
      );

      expect(result.ok, isFalse);
      expect(await fs.readString('/tp/providers/grok/xai/credential.json'),
          isNull);
    });

    test('importGlobal imports the machine auth.json', () async {
      await fs.ensureDir('/home/test/.grok');
      await fs.atomicWrite(
        '/home/test/.grok/auth.json',
        jsonEncode(_authJsonPayload()),
      );

      final result = await capability.execute(
        providerId: 'xai',
        kind: ProviderCredentialActionKind.importGlobal,
      );

      expect(result.ok, isTrue);
      expect(await readCredential(), contains('rt'));
    });

    test('materializeSessionHome fails before spawn without a credential',
        () async {
      final service = ConfigProfileService(
        basePath: '/tp',
        fs: fs,
        layout: RuntimeLayout(teampilotRoot: '/tp', fs: fs),
        storage: fakeHomeStorage(filesystem: fs),
      );
      const member = TeamMemberConfig(
        id: 'm1',
        name: 'Member',
        provider: 'xai',
      );
      final scope = resolveLaunchProfileScope(
        workspaceId: 'workspace-1',
        teamId: 'team-a',
        appSessionId: 'session-1',
        cliTeamName: 'session-1',
      );

      await expectLater(
        capability.materializeSessionHome(
          sessionHomeContextFromLaunch(
            ConfigProfileLaunchContext(
              workspaceId: 'workspace-1',
              teamId: 'team-a',
              sessionId: scope.sessionId,
              scope: scope,
              member: member,
              members: const [member],
              workingDirectory: '/workspace/workspace',
              paths: service,
              catalog: service,
              agentStatus: _agentStatus,
            ),
            CliTool.grok,
          ),
        ),
        throwsA(
          isA<GrokCredentialUnavailableException>().having(
            (error) => error.health,
            'health',
            CredentialHealth.missing,
          ),
        ),
      );
    });
  });

  test(
    'materializeSessionHome maps a transient refresh failure without leaking it',
    () async {
      final fs = InMemoryFilesystem();
      final storage = fakeHomeStorage(filesystem: fs);
      final service = ConfigProfileService(
        basePath: '/tp',
        fs: fs,
        layout: RuntimeLayout(teampilotRoot: '/tp', fs: fs),
        storage: storage,
      );
      final now = DateTime.utc(2026, 11, 14, 11, 0, 0);
      final authority = OAuthCredentialAuthority(
        fs: fs,
        basePath: '/tp',
        cliNamespace: 'grok',
        refresher: _TransientRefresher(),
        now: () => now,
      );
      // Expired access token forces a refresh, which fails transiently.
      await authority.importFromLogin(
        'xai',
        utf8.encode(
          jsonEncode({
            'scope': {
              'key': 'stale',
              'refresh_token': 'rt',
              'expires_at': '2026-11-14T10:00:00Z',
            },
          }),
        ),
      );
      final capability = GrokProviderCapability(
        storage: storage,
        authority: authority,
        adapter: GrokCredentialAdapter(
          authority: authority,
          sessionProviderId: (_) => 'xai',
          isWindows: false,
          now: () => now,
        ),
      );
      const member = TeamMemberConfig(
        id: 'm1',
        name: 'Member',
        provider: 'xai',
      );
      final scope = resolveLaunchProfileScope(
        workspaceId: 'workspace-1',
        teamId: 'team-a',
        appSessionId: 'session-1',
        cliTeamName: 'session-1',
      );

      try {
        await capability.materializeSessionHome(
          sessionHomeContextFromLaunch(
            ConfigProfileLaunchContext(
              workspaceId: 'workspace-1',
              teamId: 'team-a',
              sessionId: scope.sessionId,
              scope: scope,
              member: member,
              members: const [member],
              workingDirectory: '/workspace/workspace',
              paths: service,
              catalog: service,
              agentStatus: _agentStatus,
            ),
            CliTool.grok,
          ),
        );
        fail('expected a launch failure');
      } on GrokCredentialTransientException catch (error) {
        // The raw internal cause must not leak into the error text.
        expect(error.toString(), isNot(contains('SECRET_INTERNAL')));
        expect(error.toString(), isNot(contains('CredentialTransientException')));
      }
    },
  );

  group('ACP auth surface', () {
    test('authenticate method is grok.com except for API-key seats', () async {
      const acp = GrokAcpCapability();
      expect(acp.authenticateMethodId, GrokConstants.oauthMethodId);
      expect(
        await acp.resolveAuthenticateMethodId({
          GrokConstants.homeEnvKey: '/runtime/grok',
        }),
        GrokConstants.oauthMethodId,
      );
      // An API-key seat already carries the key; OAuth authenticate would
      // start a sign-in flow that seat does not need.
      expect(
        await acp.resolveAuthenticateMethodId({
          GrokConstants.homeEnvKey: '/runtime/grok',
          GrokConstants.apiKeyEnvKey: 'xai-key',
        }),
        isNull,
      );
    });

    test('OAuth seats do not fall back to the app-wide API key', () {
      const acp = GrokAcpCapability(credentialSource: _appWideKey);

      final oauthEnv = acp.buildEnvironment(
        sessionToolDir: '/runtime/grok',
        workingDirectory: '/work',
        baseEnv: const {
          GrokConstants.authProviderCommandEnvKey: "sh '/runtime/grok/bin/x'",
        },
      );
      expect(oauthEnv, isNot(contains(GrokConstants.apiKeyEnvKey)));

      final apiKeyEnv = acp.buildEnvironment(
        sessionToolDir: '/runtime/grok',
        workingDirectory: '/work',
      );
      expect(apiKeyEnv[GrokConstants.apiKeyEnvKey], 'app-wide-key');

      // A provider-bound key always wins over the app-wide fallback.
      final boundEnv = acp.buildEnvironment(
        sessionToolDir: '/runtime/grok',
        workingDirectory: '/work',
        baseEnv: const {GrokConstants.apiKeyEnvKey: 'seat-key'},
      );
      expect(boundEnv[GrokConstants.apiKeyEnvKey], 'seat-key');
    });
  });
}

String? _appWideKey() => 'app-wide-key';
