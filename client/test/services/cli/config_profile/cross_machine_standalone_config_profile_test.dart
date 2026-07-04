import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/models/cli_preset.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/workspace_agent_config.dart';
import 'package:teampilot/models/personal_profile.dart';
import 'package:teampilot/repositories/app_provider_repository.dart';
import 'package:teampilot/services/cli/registry/config_profile/flashskyai_config_profile_capability.dart';
import 'package:teampilot/services/cli/registry/config_profile/opencode_config_profile_capability.dart';
import 'package:teampilot/services/provider/config_profile_service.dart';
import 'package:teampilot/services/provider/control_plane_profile_paths.dart';
import 'package:teampilot/services/provider/opencode/opencode_data_layout.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/storage/runtime_context.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';

import '../../../support/in_memory_filesystem.dart';

RuntimeContext _memoryContext(String dir, InMemoryFilesystem fs) =>
    RuntimeContext(
      target: RuntimeTarget.local(),
      filesystem: fs,
      home: dir,
      cwd: dir,
      appDataRoot: dir,
      paths: AppPaths(dir),
    );

void main() {
  group('crossMachine standalone launch', () {
    test(
      'opencode materializes official auth into OPENCODE_AUTH_CONTENT',
      () async {
        const layout = OpencodeDataLayout();
        final homeFs = InMemoryFilesystem();
        final workFs = InMemoryFilesystem();
        final catalog = ControlPlaneProfilePaths(
          _memoryContext('/home-catalog', homeFs),
        );
        final workPaths = ConfigProfileService(
          basePath: '/work',
          home: '/work-home',
          fs: workFs,
          layout: _memoryContext('/work', workFs).layout,
          catalog: catalog,
        );
        const providerId = 'openai';
        final authPath = layout.providerAuthJsonPath(
          homeFs.pathContext.join(
            catalog.basePath,
            'providers',
            'opencode',
            providerId,
          ),
        );
        await homeFs.ensureDir(homeFs.pathContext.dirname(authPath));
        await homeFs.writeString(
          authPath,
          '{"openai":{"type":"api","key":"sk-remote"}}',
        );
        await AppProviderRepository(
          basePath: catalog.basePath,
          fs: homeFs,
        ).saveProviders(CliTool.opencode, [
          const AppProviderConfig(
            id: providerId,
            cli: CliTool.opencode,
            name: 'OpenAI',
            category: AppProviderCategory.official,
            isOfficial: true,
            config: {},
          ),
        ]);

        const profile = PersonalProfile(
          id: 'workspace-1',
          display: 'workspace-1',
          agent: WorkspaceAgentConfig(agent: 'solo'),
          providerIdsByTool: {'opencode': providerId},
        );
        const standalone = StandaloneLaunchProfileScope(
          workspaceId: 'workspace-1',
          sessionId: 'session-1',
        );
        const preset = CliPreset(
          id: 'opencode-default',
          name: 'OpenCode',
          cli: CliTool.opencode,
          provider: providerId,
          model: 'gpt-4',
          createdAt: 0,
          updatedAt: 0,
        );
        final scope = resolveLaunchProfileScope(
          workspaceId: 'workspace-1',
          teamId: 'workspace-1',
          appSessionId: 'session-1',
          cliTeamName: 'session-1',
        );

        final contribution = await const OpencodeConfigProfileCapability()
            .contributeLaunch(
              ConfigProfileLaunchContext(
                workspaceId: 'workspace-1',
                teamId: '',
                sessionId: 'session-1',
                scope: scope,
                personal: profile,
                members: const [],
                paths: workPaths,
                catalog: catalog,
                standaloneScope: standalone,
                preset: preset,
              ),
            );

        expect(contribution.warnings, isEmpty);
        expect(
          contribution.environment['OPENCODE_AUTH_CONTENT'],
          contains('sk-remote'),
        );
      },
    );

    test('flashskyai materializes llm_config.json onto work plane', () async {
      final homeFs = InMemoryFilesystem();
      final workFs = InMemoryFilesystem();
      final catalog = ControlPlaneProfilePaths(
        _memoryContext('/home-catalog', homeFs),
      );
      final workPaths = ConfigProfileService(
        basePath: '/work',
        home: '/work-home',
        fs: workFs,
        layout: _memoryContext('/work', workFs).layout,
        catalog: catalog,
      );
      final catalogLayout = RuntimeLayout(
        teampilotRoot: catalog.basePath,
        fs: homeFs,
      );
      await homeFs.ensureDir(
        homeFs.pathContext.dirname(catalogLayout.appFlashskyaiLlmConfigFile),
      );
      await homeFs.writeString(
        catalogLayout.appFlashskyaiLlmConfigFile,
        '{"providers":{"openai":{"api_key":"remote-key"}},"models":{}}',
      );

      const profile = PersonalProfile(
        id: 'workspace-1',
        display: 'workspace-1',
        agent: WorkspaceAgentConfig(agent: 'solo'),
      );
      const standalone = StandaloneLaunchProfileScope(
        workspaceId: 'workspace-1',
        sessionId: 'session-1',
      );
      final scope = resolveLaunchProfileScope(
        workspaceId: 'workspace-1',
        teamId: 'workspace-1',
        appSessionId: 'session-1',
        cliTeamName: 'session-1',
      );

      final contribution = await const FlashskyaiConfigProfileCapability()
          .contributeLaunch(
            ConfigProfileLaunchContext(
              workspaceId: 'workspace-1',
              teamId: '',
              sessionId: 'session-1',
              scope: scope,
              personal: profile,
              members: const [],
              paths: workPaths,
              catalog: catalog,
              standaloneScope: standalone,
            ),
          );

      expect(contribution.warnings, isEmpty);
      final workLayout = RuntimeLayout(
        teampilotRoot: workPaths.basePath,
        fs: workFs,
      );
      expect(
        contribution.environment['LLM_CONFIG_PATH'],
        workLayout.appFlashskyaiLlmConfigFile,
      );
      expect(
        await workFs.readString(workLayout.appFlashskyaiLlmConfigFile),
        contains('remote-key'),
      );
    });
  });
}
