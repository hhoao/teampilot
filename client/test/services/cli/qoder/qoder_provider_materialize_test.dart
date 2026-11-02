import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/models/credential_action_result.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/chat/launch/config_profile_service.dart';
import 'package:teampilot/services/cli/qoder/capabilities/provider.dart';
import 'package:teampilot/services/cli/registry/capabilities/provider_capability.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';

import '../../../support/in_memory_filesystem.dart';

void main() {
  test('seeds the session config dir from the provider auth store', () async {
    final fs = InMemoryFilesystem();
    final storage = fakeHomeStorage(filesystem: fs);
    final service = ConfigProfileService(
      basePath: '/tp',
      fs: fs,
      layout: RuntimeLayout(teampilotRoot: '/tp', fs: fs),
      storage: storage,
    );
    final capability = QoderProviderCapability(storage: storage);

    await fs.ensureDir('/tp/providers/qoder/work');
    await fs.atomicWrite('/tp/providers/qoder/work/user', 'USER');
    await fs.atomicWrite('/tp/providers/qoder/work/machine_id', 'MID');
    // A machine login exists too: the provider row must win and stay untouched.
    await fs.ensureDir('/home/test/.qoder/.auth');
    await fs.atomicWrite('/home/test/.qoder/.auth/user', 'MACHINE');
    await fs.atomicWrite('/home/test/.qoder/.auth/machine_id', 'M2');
    final machineAuthBefore = await fs.listDirRecursive('/home/test/.qoder');

    const member = TeamMemberConfig(id: 'm1', name: 'Member', provider: 'work');
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
        ),
        CliTool.qoder,
      ),
    );

    final configDir =
        contribution.environment[QoderProviderCapability.configDirEnvKey]!;
    expect(
      await fs.readString(p.posix.join(configDir, '.auth', 'user')),
      'USER',
    );
    expect(
      await fs.readString(p.posix.join(configDir, '.auth', 'machine_id')),
      'MID',
    );
    expect(
      (await fs.stat(p.posix.join(configDir, 'settings.json'))).isFile,
      isTrue,
      reason: 'seeding must not replace the settings write',
    );
    expect(
      await fs.readString('/home/test/.qoder/.auth/user'),
      'MACHINE',
      reason: 'the machine login is a read-only copy source',
    );
    expect(
      await fs.listDirRecursive('/home/test/.qoder'),
      machineAuthBefore,
      reason: 'the machine ~/.qoder tree is never modified',
    );
  });

  test('materializes QODER_CONFIG_DIR, model and settings.json', () async {
    final base = await Directory.systemTemp.createTemp('qoder_cap_');
    addTearDown(() async {
      if (await base.exists()) await base.delete(recursive: true);
    });

    final fs = LocalFilesystem();
    final storage = fakeHomeStorage();
    final service = ConfigProfileService(
      basePath: base.path,
      fs: fs,
      layout: RuntimeLayout(teampilotRoot: base.path, fs: fs),
      storage: storage,
    );
    final capability = QoderProviderCapability(storage: storage);

    const member = TeamMemberConfig(
      id: 'm1',
      name: 'Member',
      model: 'qwen3.8-flash',
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
        ),
        CliTool.qoder,
      ),
    );

    final expectedDir = p.join(
      base.path,
      'workspace',
      'workspaces',
      'workspace-1',
      'sessions',
      'session-1',
      'runtime',
      'qoder',
    );
    expect(
      contribution.environment[QoderProviderCapability.configDirEnvKey],
      expectedDir,
    );
    final settings = await fs.readString(p.join(expectedDir, 'settings.json'));
    expect(settings, contains('qwen3.8-flash'));
  });

  test('falls back to the provider row model and effort', () async {
    final base = await Directory.systemTemp.createTemp('qoder_cap_');
    addTearDown(() async {
      if (await base.exists()) await base.delete(recursive: true);
    });

    final fs = LocalFilesystem();
    final storage = fakeHomeStorage();
    final service = ConfigProfileService(
      basePath: base.path,
      fs: fs,
      layout: RuntimeLayout(teampilotRoot: base.path, fs: fs),
      storage: storage,
    );
    final capability = QoderProviderCapability(storage: storage);

    // Catalog row chosen by the member binding: no member model, so the
    // provider's defaultModel + reasoningEffort must win.
    await fs.ensureDir(p.join(base.path, 'providers', 'qoder'));
    await fs.atomicWrite(
      p.join(base.path, 'providers', 'qoder', 'providers.json'),
      jsonEncode({
        'providers': {
          'work': {
            'id': 'work',
            'cli': 'qoder',
            'name': 'Work',
            'defaultModel': 'glm-5.3',
            'config': {'reasoningEffort': 'high'},
          },
        },
      }),
    );

    const member = TeamMemberConfig(id: 'm1', name: 'Member', provider: 'work');
    final scope = resolveLaunchProfileScope(
      workspaceId: 'workspace-1',
      teamId: 'team-a',
      appSessionId: 'session-1',
      cliTeamName: 'session-1',
    );

    final configDir = p.join(
      base.path,
      'workspace',
      'workspaces',
      'workspace-1',
      'sessions',
      'session-1',
      'runtime',
      'qoder',
    );
    // Unrelated keys already on disk must survive the merge.
    await fs.ensureDir(configDir);
    await fs.atomicWrite(
      p.join(configDir, 'settings.json'),
      jsonEncode({'telemetry': false}),
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
        ),
        CliTool.qoder,
      ),
    );

    expect(
      contribution.environment[QoderProviderCapability.configDirEnvKey],
      configDir,
    );
    final settings =
        jsonDecode((await fs.readString(p.join(configDir, 'settings.json')))!)
            as Map<String, Object?>;
    expect(settings['model'], 'glm-5.3');
    expect(settings['reasoningEffort'], 'high');
    expect(settings['telemetry'], isFalse);
  });

  test(
    'seeds the team default provider when the member has no binding',
    () async {
      final base = await Directory.systemTemp.createTemp('qoder_cap_');
      addTearDown(() async {
        if (await base.exists()) await base.delete(recursive: true);
      });

      final catalogFs = LocalFilesystem();
      // Home plane: holds both the provider store and the machine fallback, so a
      // wrong provider id would silently seed the machine account.
      final homeFs = InMemoryFilesystem();
      final storage = fakeHomeStorage(filesystem: homeFs, appDataRoot: '/tp');
      final service = ConfigProfileService(
        basePath: base.path,
        fs: catalogFs,
        layout: RuntimeLayout(teampilotRoot: base.path, fs: catalogFs),
        storage: storage,
      );
      final capability = QoderProviderCapability(storage: storage);

      await catalogFs.ensureDir(p.join(base.path, 'providers', 'qoder'));
      await catalogFs.atomicWrite(
        p.join(base.path, 'providers', 'qoder', 'providers.json'),
        jsonEncode({
          'providers': {
            'work': {
              'id': 'work',
              'cli': 'qoder',
              'name': 'Work',
              'defaultModel': 'glm-5.3',
            },
          },
        }),
      );
      await homeFs.ensureDir('/tp/providers/qoder/work');
      await homeFs.atomicWrite('/tp/providers/qoder/work/user', 'WORK');
      await homeFs.atomicWrite('/tp/providers/qoder/work/machine_id', 'MID');
      await homeFs.ensureDir('/home/test/.qoder/.auth');
      await homeFs.atomicWrite('/home/test/.qoder/.auth/user', 'MACHINE');
      await homeFs.atomicWrite('/home/test/.qoder/.auth/machine_id', 'MID2');

      const member = TeamMemberConfig(id: 'm1', name: 'Member');
      const team = TeamProfile(
        id: 'team-a',
        name: 'Team',
        cli: CliTool.qoder,
        providerIdsByTool: {'qoder': 'work'},
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
            team: team,
            member: member,
            members: const [member],
            workingDirectory: '/workspace/workspace',
            paths: service,
            catalog: service,
          ),
          CliTool.qoder,
        ),
      );

      final configDir =
          contribution.environment[QoderProviderCapability.configDirEnvKey]!;
      expect(
        await homeFs.readString(p.posix.join(configDir, '.auth', 'user')),
        'WORK',
        reason: 'the team default provider account must seed the session',
      );
      expect(
        await homeFs.readString(p.posix.join(configDir, '.auth', 'machine_id')),
        'MID',
      );
      final settings =
          jsonDecode(
                (await catalogFs.readString(
                  p.join(configDir, 'settings.json'),
                ))!,
              )
              as Map<String, Object?>;
      expect(settings['model'], 'glm-5.3');
    },
  );

  group('probe / execute', () {
    const provider = AppProviderConfig(
      id: 'qoder',
      cli: CliTool.qoder,
      name: 'Qoder',
      isOfficial: true,
    );

    test(
      'probes missing until the provider store holds both auth files',
      () async {
        final fs = InMemoryFilesystem();
        final storage = fakeHomeStorage(filesystem: fs);
        final capability = QoderProviderCapability(storage: storage);

        final before = await capability.probe(provider);
        expect(before.isReady, isFalse);
        expect(before.credentialPath, '/tp/providers/qoder/qoder');

        final loginAuth = '/tp/cli-login/qoder/qoder/config/.auth';
        await fs.ensureDir(loginAuth);
        await fs.atomicWrite(p.join(loginAuth, 'user'), 'USER');
        await fs.atomicWrite(p.join(loginAuth, 'machine_id'), 'MID');

        final result = await capability.execute(
          providerId: provider.id,
          kind: ProviderCredentialActionKind.login,
        );
        expect(result.ok, isTrue);
        expect(await fs.readString('/tp/providers/qoder/qoder/user'), 'USER');
        expect(
          await fs.readString('/tp/providers/qoder/qoder/machine_id'),
          'MID',
        );

        expect((await capability.probe(provider)).isReady, isTrue);
      },
    );

    test('a partial provider store never probes ready', () async {
      final fs = InMemoryFilesystem();
      final storage = fakeHomeStorage(filesystem: fs);
      final capability = QoderProviderCapability(storage: storage);
      await fs.ensureDir('/tp/providers/qoder/qoder');
      await fs.atomicWrite('/tp/providers/qoder/qoder/user', 'USER');

      expect((await capability.probe(provider)).isReady, isFalse);
    });

    test('login without a captured auth pair fails verification', () async {
      final storage = fakeHomeStorage();
      final capability = QoderProviderCapability(storage: storage);
      final result = await capability.execute(
        providerId: provider.id,
        kind: ProviderCredentialActionKind.login,
      );
      expect(result.ok, isFalse);
      expect(result.failure?.code, CredentialActionFailureCode.verifyFailed);
    });

    test('non-login actions are unsupported', () async {
      final storage = fakeHomeStorage();
      final capability = QoderProviderCapability(storage: storage);
      final result = await capability.execute(
        providerId: provider.id,
        kind: ProviderCredentialActionKind.revoke,
      );
      expect(result.ok, isFalse);
      expect(result.failure?.code, CredentialActionFailureCode.unsupported);
    });

    test('without home storage the probe reports missing', () async {
      const capability = QoderProviderCapability();
      final probe = await capability.probe(provider);
      expect(probe.isReady, isFalse);
      expect(probe.credentialPath, isEmpty);

      final result = await capability.execute(
        providerId: provider.id,
        kind: ProviderCredentialActionKind.login,
      );
      expect(
        result.failure?.code,
        CredentialActionFailureCode.serviceUnavailable,
      );
    });
  });
}
