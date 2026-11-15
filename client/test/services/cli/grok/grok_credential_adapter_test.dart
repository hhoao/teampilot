import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/credential_lease.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/chat/launch/config_profile_service.dart';
import 'package:teampilot/services/chat/team_bus/member_bus_idle_endpoint.dart';
import 'package:teampilot/services/cli/grok/grok_constants.dart';
import 'package:teampilot/services/cli/grok/provider/grok_credential_adapter.dart';
import 'package:teampilot/services/cli/registry/capabilities/provider_capability.dart';
import 'package:teampilot/services/provider/oauth_credential_authority.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';

import '../../../support/in_memory_filesystem.dart';

final class _OkRefresher implements CredentialRefresher {
  @override
  Future<CredentialRefreshOutcome> refresh(String refreshToken) async =>
      RefreshSucceeded(
        accessToken: 'fresh',
        refreshToken: 'rt-fresh',
        expiresAt: DateTime.utc(2026, 11, 14, 12, 0, 0),
      );
}

void main() {
  const localBusIdle = MemberBusIdleEndpoint(
    url: 'http://127.0.0.1:35297/idle',
  );

  SessionHomeContext context(
    ConfigProfileService service, {
    MemberBusIdleEndpoint? busIdle,
    bool withoutBusIdle = false,
  }) => sessionHomeContextFromLaunch(
    ConfigProfileLaunchContext(
      workspaceId: 'workspace-1',
      teamId: 'team-a',
      sessionId: 'session-1',
      scope: resolveLaunchProfileScope(
        workspaceId: 'workspace-1',
        teamId: 'team-a',
        appSessionId: 'session-1',
        cliTeamName: 'session-1',
      ),
      member: const TeamMemberConfig(
        id: 'm1',
        name: 'Member',
        provider: 'xai',
        model: 'grok-4.7',
      ),
      members: const [
        TeamMemberConfig(
          id: 'm1',
          name: 'Member',
          provider: 'xai',
          model: 'grok-4.7',
        ),
      ],
      workingDirectory: '/workspace/workspace',
      paths: service,
      catalog: service,
      busIdle: withoutBusIdle ? null : (busIdle ?? localBusIdle),
    ),
    CliTool.grok,
  );

  Future<GrokCredentialAdapter> build() async {
    final fs = InMemoryFilesystem();
    final authority = OAuthCredentialAuthority(
      fs: fs,
      basePath: '/tp',
      cliNamespace: 'grok',
      refresher: _OkRefresher(),
      now: () => DateTime.utc(2026, 11, 14, 11, 0, 0),
    );
    await authority.importFromLogin(
      'xai',
      utf8.encode(
        jsonEncode({
          'scope': {
            'key': 'access-old',
            'refresh_token': 'rt-old',
            'expires_at': '2026-11-14T11:30:00Z',
          },
        }),
      ),
    );
    return GrokCredentialAdapter(
      authority: authority,
      sessionProviderId: (_) => 'xai',
      now: () => DateTime.utc(2026, 11, 14, 11, 0, 0),
    );
  }

  ConfigProfileService serviceOn(InMemoryFilesystem fs) => ConfigProfileService(
    basePath: '/tp',
    fs: fs,
    layout: RuntimeLayout(teampilotRoot: '/tp', fs: fs),
    storage: fakeHomeStorage(filesystem: fs),
  );

  test(
    'injects GROK_AUTH_PROVIDER_COMMAND and writes shim + lease config',
    () async {
      final adapter = await build();
      final fs = InMemoryFilesystem();
      final service = serviceOn(fs);

      final contribution = await adapter.materialize(
        context(service),
        providerId: 'xai',
      );

      final configDir = contribution.environment[GrokConstants.homeEnvKey]!;
      expect(
        contribution.environment[GrokConstants.authProviderCommandEnvKey],
        p.posix.join(configDir, 'bin', GrokConstants.leaseShimFileName),
      );
      expect(
        contribution.environment,
        isNot(contains(GrokConstants.apiKeyEnvKey)),
      );
      expect(contribution.warnings, isEmpty);

      final shim = await fs.readString(
        p.posix.join(configDir, 'bin', GrokConstants.leaseShimFileName),
      );
      expect(shim, contains('/credentials/lease'));
      expect(shim, contains('GROK_AUTH_EXPIRED'));

      final leaseConfig =
          jsonDecode(
                (await fs.readString(
                  p.posix.join(configDir, GrokConstants.leaseConfigFileName),
                ))!,
              )
              as Map<String, Object?>;
      expect(leaseConfig['providerId'], 'xai');
      expect(
        leaseConfig['endpoint'],
        'http://127.0.0.1:35297/credentials/lease',
      );
      expect(jsonEncode(leaseConfig), isNot(contains('access-old')));
      expect(jsonEncode(leaseConfig), isNot(contains('rt-old')));
    },
  );

  test(
    'shim forwards only access_token/expires_in from the lease response',
    () async {
      final adapter = await build();
      final fs = InMemoryFilesystem();
      final service = serviceOn(fs);

      final contribution = await adapter.materialize(
        context(service),
        providerId: 'xai',
      );
      final configDir = contribution.environment[GrokConstants.homeEnvKey]!;
      final shim = (await fs.readString(
        p.posix.join(configDir, 'bin', GrokConstants.leaseShimFileName),
      ))!;

      // The endpoint's 200 body also carries `epoch`; grok's contract allows
      // exactly these two fields, so the raw response must not be echoed.
      expect(
        shim,
        contains(r'''printf '{"access_token":"%s","expires_in":%s}\n' '''),
      );
      expect(shim, isNot(contains(r'''printf '%s\n' "$RESP"''')));
    },
  );

  test('no auth.json is seeded into the session home', () async {
    final adapter = await build();
    final fs = InMemoryFilesystem();
    final service = serviceOn(fs);

    final contribution = await adapter.materialize(
      context(service),
      providerId: 'xai',
    );
    final configDir = contribution.environment[GrokConstants.homeEnvKey]!;

    expect(await fs.readString(p.posix.join(configDir, 'auth.json')), isNull);
  });

  test(
    'remote seat uses the idle HTTP tunnel endpoint and bus token',
    () async {
      final adapter = await build();
      final fs = InMemoryFilesystem();
      final service = serviceOn(fs);
      const busIdle = MemberBusIdleEndpoint(
        url: 'http://127.0.0.1:41001/idle',
        token: 'bus-secret',
      );

      final contribution = await adapter.materialize(
        context(service, busIdle: busIdle),
        providerId: 'xai',
      );
      final configDir = contribution.environment[GrokConstants.homeEnvKey]!;
      final leaseConfig =
          jsonDecode(
                (await fs.readString(
                  p.posix.join(configDir, GrokConstants.leaseConfigFileName),
                ))!,
              )
              as Map<String, Object?>;

      expect(
        leaseConfig['endpoint'],
        'http://127.0.0.1:41001/credentials/lease',
      );
      expect(leaseConfig['sessionId'], 'session-1');
      expect(leaseConfig['memberId'], 'm1');
      expect(leaseConfig['busToken'], 'bus-secret');
    },
  );

  test(
    'expired/rejected credential fails before launch with a warning',
    () async {
      final fs = InMemoryFilesystem();
      final authority = OAuthCredentialAuthority(
        fs: fs,
        basePath: '/tp',
        cliNamespace: 'grok',
        refresher: _OkRefresher(),
        now: () => DateTime.utc(2026, 11, 14, 11, 0, 0),
      );
      final adapter = GrokCredentialAdapter(
        authority: authority,
        sessionProviderId: (_) => 'xai',
        now: () => DateTime.utc(2026, 11, 14, 11, 0, 0),
      );
      final service = serviceOn(fs);

      expect(
        () => adapter.materialize(context(service), providerId: 'xai'),
        throwsA(isA<CredentialUnavailableException>()),
      );
    },
  );

  test(
    'onAuthRequired recovers once and credentialStatus reflects health',
    () async {
      final adapter = await build();

      expect(await adapter.credentialStatus('xai'), CredentialHealth.ready);
      expect(
        await adapter.onAuthRequired(providerId: 'xai', sessionId: 'session-1'),
        isTrue,
      );
    },
  );

  test('no reachable lease endpoint fails before launch', () async {
    final adapter = await build();
    final fs = InMemoryFilesystem();
    final service = serviceOn(fs);

    expect(
      () => adapter.materialize(
        context(service, withoutBusIdle: true),
        providerId: 'xai',
      ),
      throwsA(isA<CredentialUnavailableException>()),
    );
  });

  test('a seat may only materialize the provider it launched with', () async {
    final adapter = await build();
    final fs = InMemoryFilesystem();
    final service = serviceOn(fs);

    expect(
      () => adapter.materialize(context(service), providerId: 'other'),
      throwsA(isA<CredentialUnavailableException>()),
    );
  });
}
