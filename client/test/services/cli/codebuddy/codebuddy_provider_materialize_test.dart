import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/chat/launch/config_profile_service.dart';
import 'package:teampilot/services/cli/codebuddy/capabilities/provider.dart';
import 'package:teampilot/services/cli/registry/capabilities/provider_capability.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';

import '../../../support/in_memory_filesystem.dart';

void main() {
  Future<SessionHomeContribution> contribute(
    CodebuddyProviderCapability capability,
    ConfigProfileLaunchContext ctx,
  ) => capability.materializeSessionHome(
    sessionHomeContextFromLaunch(ctx, CliTool.codebuddy),
  );

  test('materializes CODEBUDDY_CONFIG_DIR and the provider model', () async {
    final base = await Directory.systemTemp.createTemp('codebuddy_cap_');
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
    final capability = CodebuddyProviderCapability(storage: storage);

    const member = TeamMemberConfig(
      id: 'm1',
      name: 'Member',
      provider: 'custom-endpoint',
      model: 'gpt-5',
    );
    final scope = resolveLaunchProfileScope(
      workspaceId: 'workspace-1',
      teamId: 'team-a',
      appSessionId: 'session-1',
      cliTeamName: 'session-1',
    );

    final contribution = await contribute(
      capability,
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
    );

    final expectedDir = p.join(
      base.path,
      'workspace',
      'workspaces',
      'workspace-1',
      'sessions',
      'session-1',
      'runtime',
      'codebuddy',
    );
    expect(
      contribution.environment[CodebuddyProviderCapability.configDirEnvKey],
      expectedDir,
    );
  });

  test('writes settings.json + models.json for a custom provider', () async {
    final base = await Directory.systemTemp.createTemp('codebuddy_cap_');
    addTearDown(() async {
      if (await base.exists()) await base.delete(recursive: true);
    });

    final fs = LocalFilesystem();
    final memFs = InMemoryFilesystem();
    final storage = fakeHomeStorage(filesystem: memFs, appDataRoot: base.path);
    // Provider-scoped isolated credential (injected as CODEBUDDY_AUTH_TOKEN).
    await memFs.ensureDir(p.join(base.path, 'providers', 'codebuddy'));
    await memFs.atomicWrite(
      p.join(base.path, 'providers', 'codebuddy', 'custom-endpoint.auth.json'),
      jsonEncode({
        'accessToken': 'tok-custom',
        'expiresAt': DateTime.now()
            .add(const Duration(days: 10))
            .millisecondsSinceEpoch,
      }),
    );
    // Catalog row consumed by CodebuddyProviderSettingsResolver.
    final providersPath = p.join(
      base.path,
      'providers',
      'codebuddy',
      'providers.json',
    );
    await fs.ensureDir(p.dirname(providersPath));
    await fs.atomicWrite(
      providersPath,
      jsonEncode({
        'providers': {
          'custom-endpoint': {
            'id': 'custom-endpoint',
            'cli': 'codebuddy',
            'name': 'Custom',
            'baseUrl': 'https://api.example.com/v1',
            'apiKey': 'sk-secret',
            'defaultModel': 'gpt-5',
          },
        },
      }),
    );

    final service = ConfigProfileService(
      basePath: base.path,
      fs: fs,
      layout: RuntimeLayout(teampilotRoot: base.path, fs: fs),
      storage: storage,
    );
    final capability = CodebuddyProviderCapability(storage: storage);
    const member = TeamMemberConfig(
      id: 'm1',
      name: 'Member',
      provider: 'custom-endpoint',
    );
    final scope = resolveLaunchProfileScope(
      workspaceId: 'workspace-1',
      teamId: 'team-a',
      appSessionId: 'session-1',
      cliTeamName: 'session-1',
    );

    final contribution = await contribute(
      capability,
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
    );

    final configDir =
        contribution.environment[CodebuddyProviderCapability.configDirEnvKey]!;
    expect(contribution.environment['CODEBUDDY_API_KEY'], 'sk-secret');
    expect(
      contribution.environment['CODEBUDDY_BASE_URL'],
      'https://api.example.com/v1',
    );
    expect(contribution.environment['CODEBUDDY_AUTH_TOKEN'], 'tok-custom');

    final settings =
        jsonDecode((await fs.readString(p.join(configDir, 'settings.json')))!)
            as Map<String, Object?>;
    expect(settings['model'], 'gpt-5');

    final modelsRaw = (await fs.readString(p.join(configDir, 'models.json')))!;
    expect(
      modelsRaw,
      isNot(contains('sk-secret')),
      reason: 'the API key must stay in the process env',
    );
    final models = jsonDecode(modelsRaw) as Map<String, Object?>;
    final row = (models['models'] as List).single as Map<String, Object?>;
    expect(row['id'], 'gpt-5');
    expect(row['apiKey'], r'${CODEBUDDY_API_KEY}');
    expect(row['url'], 'https://api.example.com/v1/chat/completions');
  });
}
