import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/chat/launch/config_profile_service.dart';
import 'package:teampilot/services/chat/launch/staging/manifest/launch_manifest.dart';
import 'package:teampilot/services/chat/launch/staging/manifest/manifest_filesystem.dart';
import 'package:teampilot/services/cli/grok/capabilities/provider.dart';
import 'package:teampilot/services/cli/grok/grok_constants.dart';
import 'package:teampilot/services/cli/registry/capabilities/provider_capability.dart';
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

void main() {
  test(
    'writes models.default and seeds auth.json from the provider store',
    () async {
      final fs = InMemoryFilesystem();
      final storage = fakeHomeStorage(filesystem: fs);
      final service = ConfigProfileService(
        basePath: '/tp',
        fs: fs,
        layout: RuntimeLayout(teampilotRoot: '/tp', fs: fs),
        storage: storage,
      );
      final capability = GrokProviderCapability(storage: storage);

      await fs.ensureDir('/tp/providers/grok/xai');
      await fs.atomicWrite(
        '/tp/providers/grok/xai/auth.json',
        '{"access_token":"provider"}',
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
          ),
          CliTool.grok,
        ),
      );

      final configDir = contribution.environment[GrokConstants.homeEnvKey]!;
      expect(contribution.environment, isNot(contains('XAI_API_KEY')));
      expect(contribution.warnings, isEmpty);
      expect(
        await fs.readString(p.posix.join(configDir, 'auth.json')),
        '{"access_token":"provider"}',
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

  test(
    'simple session seeds auth into the session tool dir ACP launches with',
    () async {
      final fs = InMemoryFilesystem();
      final storage = fakeHomeStorage(filesystem: fs);
      final service = ConfigProfileService(
        basePath: '/tp',
        fs: fs,
        layout: RuntimeLayout(teampilotRoot: '/tp', fs: fs),
        storage: storage,
      );
      final capability = GrokProviderCapability(storage: storage);

      await fs.ensureDir('/tp/providers/grok/xai');
      await fs.atomicWrite(
        '/tp/providers/grok/xai/auth.json',
        '{"access_token":"provider"}',
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
        await fs.readString(p.posix.join(expectedDir, 'auth.json')),
        '{"access_token":"provider"}',
      );
    },
  );

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
    'cross-machine stages auth.json through the work-plane manifest',
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
      final capability = GrokProviderCapability(storage: storage);

      await homeFs.ensureDir('/tp/providers/grok/xai');
      await homeFs.atomicWrite(
        '/tp/providers/grok/xai/auth.json',
        '{"access_token":"provider"}',
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
        ),
      );

      final configDir = contribution.environment[GrokConstants.homeEnvKey]!;
      expect(configDir, startsWith('/remote/tp/'));
      final copies = manifest.entries.whereType<ManifestCopyFile>().toList();
      expect(copies, isNotEmpty);
      expect(
        copies.map((c) => '${c.source} -> ${c.destination}'),
        contains('/tp/providers/grok/xai/auth.json -> $configDir/auth.json'),
      );
      expect(copies.every((c) => c.private), isTrue);
      expect(
        homeFs.files.keys.where((k) => k.startsWith(configDir)),
        isEmpty,
        reason: 'cross-machine seeding must not write through the home fs',
      );
    },
  );
}
