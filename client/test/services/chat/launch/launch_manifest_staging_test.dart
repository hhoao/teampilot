import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/models/cli_preset.dart';
import 'package:teampilot/models/config_bundle.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/app_provider_repository.dart';
import 'package:teampilot/services/chat/launch/staging/manifest/manifest_executor.dart';
import 'package:teampilot/services/chat/session/session_lifecycle_service.dart';
import 'package:teampilot/services/cli/registry/cli_bootstrap.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

import '../../../support/in_memory_filesystem.dart';
import '../../../support/post_frame_test_harness.dart';

void main() {
  setUp(() {
    setUpTestAppStorage();
    CliToolRegistry.builtIn().configure(
      CliBootstrap(const {}, storage: testHomeStorage),
    );
  });
  tearDown(tearDownTestAppStorage);

  test(
    'stageSimpleSessionLaunch records manifest entries on local target',
    () async {
      final lifecycle = SessionLifecycleService(
        appDataBasePath: testHomeStorage.paths.basePath,
        storage: testHomeStorage,
      );
      final roots = await lifecycle.resolveWorkContextForTargetId('local');
      final svc = await lifecycle.configProfileServiceFor(roots);
      final staged = await svc.stageSimpleSessionLaunch(
        readDelegate: roots.fs,
        workTeampilotRoot: roots.appDataRoot,
        workspaceId: 'ws1',
        sessionId: 'sess1',
        runtimeBundle: const ConfigBundle(),
        member: const TeamMemberConfig(id: 'default', name: 'Default'),
      );
      expect(staged.manifest.files, isNotEmpty);

      await const ManifestExecutor().flush(
        manifest: staged.manifest,
        targetFs: roots.fs,
        sourceFs: roots.fs,
        symlinkProjectionRoot: roots.appDataRoot,
        homeRoot: roots.appDataRoot,
      );
    },
  );

  test('stageTeamLaunch records manifest entries on local target', () async {
    const presetId = 'preset-deepseek';
    const providerId = 'deepseek-provider';
    final lifecycle = SessionLifecycleService(
      appDataBasePath: testHomeStorage.paths.basePath,
      loadPresets: () => const [
        CliPreset(
          id: presetId,
          name: 'DeepSeek',
          cli: CliTool.claude,
          provider: providerId,
          model: 'deepseek-v4-pro[1m]',
          createdAt: 1,
          updatedAt: 1,
        ),
      ],
      storage: testHomeStorage,
    );
    final roots = await lifecycle.resolveWorkContextForTargetId('local');
    final repository = AppProviderRepository(
      basePath: roots.appDataRoot,
      storage: testHomeStorage,
    );
    await repository.saveProviders(CliTool.claude, [
      AppProviderConfig(
        id: providerId,
        cli: CliTool.claude,
        name: providerId,
        category: AppProviderCategory.thirdParty,
        config: const {
          'env': {
            'ANTHROPIC_BASE_URL': 'https://api.deepseek.com/anthropic',
            'ANTHROPIC_AUTH_TOKEN': 'sk-test',
          },
        },
      ),
    ]);
    final svc = await lifecycle.configProfileServiceFor(roots);
    const sessionId = '00000000-0000-4000-8000-000000000099';
    const builder = TeamMemberConfig(
      id: 'builder',
      name: 'builder',
      cli: CliTool.claude,
      activePresetId: presetId,
    );
    final staged = await svc.stageTeamLaunch(
      readDelegate: roots.fs,
      workTeampilotRoot: roots.appDataRoot,
      workspaceId: 'ws1',
      sessionId: sessionId,
      teamId: 'team-a',
      cliTeamName: sessionId,
      cli: CliTool.claude,
      members: const [builder],
      member: builder,
      team: const TeamProfile(
        id: 'team-a',
        name: 'team-a',
        cli: CliTool.claude,
        teamMode: TeamMode.mixed,
        members: [builder],
      ),
      runtimeBundle: const ConfigBundle(),
    );
    expect(staged.manifest.entries, isNotEmpty);
    // Hooks may write settings/<member>.json before session-home merges env;
    // [LaunchManifest.files] keeps the last write per path.
    final settingsPath = staged.manifest.files.keys.singleWhere((path) {
      final normalized = path.replaceAll(r'\', '/');
      return normalized.endsWith('/settings/builder.json');
    });
    final settings = jsonDecode(staged.manifest.files[settingsPath]!) as Map;
    final env = (settings['env'] as Map).cast<String, Object?>();
    expect(env['ANTHROPIC_BASE_URL'], 'https://api.deepseek.com/anthropic');
    expect(env['ANTHROPIC_AUTH_TOKEN'], 'sk-test');

    await const ManifestExecutor().flush(
      manifest: staged.manifest,
      targetFs: roots.fs,
      sourceFs: roots.fs,
      symlinkProjectionRoot: roots.appDataRoot,
      homeRoot: roots.appDataRoot,
    );
  });

  test(
    'off-home stageTeamLaunch flushes mixed member settings onto the work plane',
    () async {
      final lifecycle = SessionLifecycleService(
        appDataBasePath: testHomeStorage.paths.basePath,
        storage: testHomeStorage,
      );
      final home = await lifecycle.resolveWorkContextForTargetId('local');
      final svc = await lifecycle.configProfileServiceFor(home);
      const sessionId = '00000000-0000-4000-8000-000000000021';
      const developer = TeamMemberConfig(
        id: 'developer',
        name: 'developer',
        cli: CliTool.claude,
      );
      const workRoot = '/home/testuser/.local/share/com.hhoa.teampilot';
      final workFs = InMemoryFilesystem();
      final staged = await svc.stageTeamLaunch(
        readDelegate: home.fs,
        workTeampilotRoot: workRoot,
        workspaceId: 'ws-remote',
        sessionId: sessionId,
        teamId: 'team-a',
        cliTeamName: sessionId,
        cli: CliTool.claude,
        members: const [developer],
        member: developer,
        team: const TeamProfile(
          id: 'team-a',
          name: 'team-a',
          cli: CliTool.claude,
          teamMode: TeamMode.mixed,
          members: [developer],
        ),
        runtimeBundle: const ConfigBundle(),
      );
      expect(
        staged.manifest.files.keys.any(
          (path) => path.replaceAll(r'\', '/').endsWith(
            '/settings/developer.json',
          ),
        ),
        isTrue,
        reason: 'staging must record the --settings file before SSH flush',
      );

      await const ManifestExecutor().flush(
        manifest: staged.manifest,
        targetFs: workFs,
        sourceFs: home.fs,
        symlinkProjectionRoot: workRoot,
        homeRoot: home.appDataRoot,
      );
      final settingsPath =
          '$workRoot/workspace/workspaces/ws-remote/sessions/'
          '$sessionId/runtime/developer/claude/settings/developer.json';
      expect(
        await workFs.readString(settingsPath),
        isNotNull,
        reason: 'work plane must have the file Claude --settings points at',
      );
    },
  );
}
