import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/credential_lease.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/agent_status/member_agent_status_endpoint.dart';
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
    MemberAgentStatusEndpoint? agentStatus,
    bool includeDefaultBusIdle = true,
    ConfigProfileService? catalog,
    RemoteOs? workPlaneOs,
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
      // A catalog with a different basePath makes crossMachine true (the
      // work plane is remote relative to the control plane).
      catalog: catalog ?? service,
      busIdle: includeDefaultBusIdle ? (busIdle ?? localBusIdle) : null,
      agentStatus: agentStatus,
      workPlaneOs: workPlaneOs,
    ),
    CliTool.grok,
  );

  Future<GrokCredentialAdapter> build({
    bool? isWindows,
    void Function(String sessionId, String providerId)? onSessionMaterialized,
  }) async {
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
      onSessionMaterialized: onSessionMaterialized,
      now: () => DateTime.utc(2026, 11, 14, 11, 0, 0),
      isWindows: isWindows,
    );
  }

  ConfigProfileService serviceOn(
    InMemoryFilesystem fs, {
    String basePath = '/tp',
  }) => ConfigProfileService(
    basePath: basePath,
    fs: fs,
    layout: RuntimeLayout(teampilotRoot: basePath, fs: fs),
    storage: fakeHomeStorage(filesystem: fs),
  );

  Future<Map<String, Object?>> readLeaseConfig(
    InMemoryFilesystem fs,
    String configDir,
  ) async =>
      jsonDecode(
            (await fs.readString(
              p.posix.join(configDir, GrokConstants.leaseConfigFileName),
            ))!,
          )
          as Map<String, Object?>;

  /// Executes the generated shim in a real temp dir with a fake `curl` first
  /// on PATH. Returns the process result and deletes the temp tree afterwards.
  Future<ProcessResult> runShim({
    required String shimBody,
    required String curlStdout,
    String curlStatus = '200',
  }) async {
    final tmp = Directory.systemTemp.createTempSync('grok-shim-test-');
    addTearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });
    final binDir = Directory(p.join(tmp.path, 'bin'))..createSync();
    final shimPath = p.join(binDir.path, GrokConstants.leaseShimFileName);
    File(shimPath).writeAsStringSync(shimBody);
    File(p.join(tmp.path, GrokConstants.leaseConfigFileName)).writeAsStringSync(
      jsonEncode({
        'providerId': 'xai',
        'endpoint': 'http://127.0.0.1:35297/credentials/lease',
        'sessionId': 'session-1',
        'memberId': 'm1',
        'busToken': 'session-1',
      }),
    );
    final fakeBin = Directory(p.join(tmp.path, 'fakebin'))..createSync();
    final fakeCurl = File(p.join(fakeBin.path, 'curl'));
    // Mimic `curl -w '\n%{http_code}'`: body followed by a newline + status.
    fakeCurl.writeAsStringSync(
      '#!/bin/sh\nprintf \'%s\\n%s\' \'$curlStdout\' \'$curlStatus\'\n',
    );
    Process.runSync('chmod', ['755', fakeCurl.path]);

    final env = Map<String, String>.from(Platform.environment);
    env['PATH'] = '${fakeBin.path}:${env['PATH'] ?? ''}';
    return Process.run('sh', [shimPath], environment: env);
  }

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
      final shimPath = p.posix.join(
        configDir,
        'bin',
        GrokConstants.leaseShimFileName,
      );
      // grok runs the command through `sh -c`; quoting keeps paths safe and
      // does not rely on a remote flush preserving the executable bit.
      expect(
        contribution.environment[GrokConstants.authProviderCommandEnvKey],
        "sh '$shimPath'",
      );
      expect(
        contribution.environment,
        isNot(contains(GrokConstants.apiKeyEnvKey)),
      );
      expect(contribution.warnings, isEmpty);

      final shim = await fs.readString(shimPath);
      expect(shim, contains('/credentials/lease'));
      expect(shim, contains('GROK_AUTH_EXPIRED'));

      final leaseConfig = await readLeaseConfig(fs, configDir);
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
    'native/simple seat uses the agent-status endpoint without a bus idle',
    () async {
      final adapter = await build();
      final fs = InMemoryFilesystem();
      final service = serviceOn(fs);
      const agentStatus = MemberAgentStatusEndpoint(
        url: 'http://127.0.0.1:35297/agent-status',
        sessionId: 'session-1',
      );

      final contribution = await adapter.materialize(
        context(
          service,
          agentStatus: agentStatus,
          includeDefaultBusIdle: false,
        ),
        providerId: 'xai',
      );
      final configDir = contribution.environment[GrokConstants.homeEnvKey]!;
      final leaseConfig = await readLeaseConfig(fs, configDir);

      expect(
        leaseConfig['endpoint'],
        'http://127.0.0.1:35297/credentials/lease',
      );
      expect(leaseConfig['sessionId'], 'session-1');
      // Local seats echo the session id as the bus token.
      expect(leaseConfig['busToken'], 'session-1');
    },
  );

  test(
    'agent-status takes precedence over the idle endpoint when both exist',
    () async {
      final adapter = await build();
      final fs = InMemoryFilesystem();
      final service = serviceOn(fs);
      const agentStatus = MemberAgentStatusEndpoint(
        url: 'http://127.0.0.1:44001/agent-status',
        token: 'status-token',
      );
      const busIdle = MemberBusIdleEndpoint(
        url: 'http://127.0.0.1:41001/idle',
        token: 'bus-secret',
      );

      final contribution = await adapter.materialize(
        context(service, agentStatus: agentStatus, busIdle: busIdle),
        providerId: 'xai',
      );
      final configDir = contribution.environment[GrokConstants.homeEnvKey]!;
      final leaseConfig = await readLeaseConfig(fs, configDir);

      expect(
        leaseConfig['endpoint'],
        'http://127.0.0.1:44001/credentials/lease',
      );
      expect(leaseConfig['busToken'], 'status-token');
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

      final result = await runShim(
        shimBody: shim,
        curlStdout: '{"access_token":"t","expires_in":900,"epoch":7}',
      );
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(result.stdout, '{"access_token":"t","expires_in":900}\n');
    },
    skip: Platform.isWindows ? 'POSIX sh shim only' : false,
  );

  test(
    'shim exits non-zero when the lease response has no access_token',
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

      final result = await runShim(
        shimBody: shim,
        curlStdout: '{"health":"missing"}',
        curlStatus: '409',
      );
      expect(result.exitCode, isNot(0));
      expect(result.stdout, isEmpty);
      expect(result.stderr.toString(), contains('sign in'));
    },
    skip: Platform.isWindows ? 'POSIX sh shim only' : false,
  );

  test(
    'shim distinguishes a transient 503 (retry) from a 409 (sign in)',
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

      final transient = await runShim(
        shimBody: shim,
        curlStdout: '{"error":"temporarily_unavailable"}',
        curlStatus: '503',
      );
      expect(transient.exitCode, isNot(0));
      expect(transient.stdout, isEmpty);
      expect(transient.stderr.toString(), contains('retry'));

      final rejected = await runShim(
        shimBody: shim,
        curlStdout: '{"health":"rejected"}',
        curlStatus: '409',
      );
      expect(rejected.exitCode, isNot(0));
      expect(rejected.stdout, isEmpty);
      expect(rejected.stderr.toString(), contains('sign in'));
      expect(rejected.stderr.toString(), isNot(contains('retry')));
    },
    skip: Platform.isWindows ? 'POSIX sh shim only' : false,
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
      final leaseConfig = await readLeaseConfig(fs, configDir);

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

  test(
    'fails before launch when agent-status and idle are both missing',
    () async {
      final adapter = await build();
      final fs = InMemoryFilesystem();
      final service = serviceOn(fs);

      expect(
        () => adapter.materialize(
          context(service, includeDefaultBusIdle: false),
          providerId: 'xai',
        ),
        throwsA(isA<CredentialUnavailableException>()),
      );
    },
  );

  test('a LOCAL windows seat fails closed before spawn', () async {
    final adapter = await build(isWindows: true);
    final fs = InMemoryFilesystem();
    final service = serviceOn(fs);

    expect(
      () => adapter.materialize(context(service), providerId: 'xai'),
      throwsA(isA<CredentialUnavailableException>()),
    );
  });

  test('a windows HOST with a remote POSIX work plane is not blocked',
      () async {
    final adapter = await build(isWindows: true);
    final fs = InMemoryFilesystem();
    final service = serviceOn(fs);
    // A different control-plane basePath means the work plane is remote; the
    // shim runs on the POSIX remote, so the host OS must not fail the launch.
    final remoteCatalog = serviceOn(fs, basePath: '/remote-control');
    final ctx = context(service, catalog: remoteCatalog);
    expect(ctx.crossMachine, isTrue);

    final contribution = await adapter.materialize(ctx, providerId: 'xai');
    expect(
      contribution.environment,
      contains(GrokConstants.authProviderCommandEnvKey),
    );
  });

  test('a custom providerId is no longer rejected (multi-provider support)',
      () async {
    final fs = InMemoryFilesystem();
    final authority = OAuthCredentialAuthority(
      fs: fs,
      basePath: '/tp',
      cliNamespace: 'grok',
      refresher: _OkRefresher(),
      now: () => DateTime.utc(2026, 11, 14, 11, 0, 0),
    );
    await authority.importFromLogin(
      'acme',
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
    // A seat launched with a real custom id must still materialize: the
    // authoritative provider check now lives on the lease endpoint, backed by
    // the session->provider registry, not a hardcoded id.
    final adapter = GrokCredentialAdapter(
      authority: authority,
      sessionProviderId: (_) => 'xai',
      now: () => DateTime.utc(2026, 11, 14, 11, 0, 0),
    );
    final service = serviceOn(fs);

    final contribution = await adapter.materialize(
      context(service),
      providerId: 'acme',
    );
    expect(
      contribution.environment,
      contains(GrokConstants.authProviderCommandEnvKey),
    );
    final configDir = contribution.environment[GrokConstants.homeEnvKey]!;
    final leaseConfig = await readLeaseConfig(fs, configDir);
    expect(leaseConfig['providerId'], 'acme');
  });

  test('registers the seat provider once materialization succeeds', () async {
    final registrations = <String>[];
    final adapter = await build(
      onSessionMaterialized: (sessionId, providerId) =>
          registrations.add('$sessionId:$providerId'),
    );
    final fs = InMemoryFilesystem();
    final service = serviceOn(fs);

    await adapter.materialize(context(service), providerId: 'xai');

    expect(registrations, ['session-1:xai']);
  });

  test('does not register a seat that failed the pre-launch gate', () async {
    final registrations = <String>[];
    final adapter = await build(
      onSessionMaterialized: (sessionId, _) => registrations.add(sessionId),
    );
    final fs = InMemoryFilesystem();
    final service = serviceOn(fs);

    // No agent-status / idle binding -> no lease endpoint -> fail closed
    // before any files are staged, so the endpoint must not learn this seat.
    expect(
      () => adapter.materialize(
        context(service, includeDefaultBusIdle: false),
        providerId: 'xai',
      ),
      throwsA(isA<CredentialUnavailableException>()),
    );
    expect(registrations, isEmpty);
  });

  test('a WINDOWS work plane fails closed even from a POSIX host', () async {
    final adapter = await build(isWindows: false);
    final fs = InMemoryFilesystem();
    final service = serviceOn(fs);
    final remoteCatalog = serviceOn(fs, basePath: '/remote-control');

    expect(
      () => adapter.materialize(
        context(
          service,
          catalog: remoteCatalog,
          workPlaneOs: RemoteOs.windows,
        ),
        providerId: 'xai',
      ),
      throwsA(isA<CredentialUnavailableException>()),
    );
  });

  test('a WINDOWS host with a POSIX work plane is not blocked', () async {
    final adapter = await build(isWindows: true);
    final fs = InMemoryFilesystem();
    final service = serviceOn(fs);
    final remoteCatalog = serviceOn(fs, basePath: '/remote-control');

    final contribution = await adapter.materialize(
      context(
        service,
        catalog: remoteCatalog,
        workPlaneOs: RemoteOs.posix,
      ),
      providerId: 'xai',
    );
    expect(
      contribution.environment,
      contains(GrokConstants.authProviderCommandEnvKey),
    );
  });
}
