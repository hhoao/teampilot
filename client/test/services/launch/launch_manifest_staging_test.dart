import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/models/cli_preset.dart';
import 'package:teampilot/models/config_bundle.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/app_provider_repository.dart';
import 'package:teampilot/services/launch/manifest_executor.dart';
import 'package:teampilot/services/session/session_lifecycle_service.dart';
import 'package:teampilot/services/storage/app_storage.dart';

import '../../support/post_frame_test_harness.dart';

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  test(
    'stageSimpleSessionLaunch records manifest entries on local target',
    () async {
      final lifecycle = SessionLifecycleService(
        appDataBasePath: AppStorage.paths.basePath,
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
      );
    },
  );

  test('stageTeamLaunch records manifest entries on local target', () async {
    const presetId = 'preset-deepseek';
    const providerId = 'deepseek-provider';
    final lifecycle = SessionLifecycleService(
      appDataBasePath: AppStorage.paths.basePath,
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
    );
    final roots = await lifecycle.resolveWorkContextForTargetId('local');
    final repository = AppProviderRepository(basePath: roots.appDataRoot);
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
    );
  });
}
