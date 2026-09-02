import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/app/team_generation_graph.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/team_generation_settings.dart';
import 'package:teampilot/services/catalog/catalog_mcp_constants.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/launch/session_shell_connector.dart';
import 'package:teampilot/services/resource/contribution/resource_origin.dart';
import 'package:teampilot/services/resource/resource_provider_set.dart';
import 'package:teampilot/services/resource/providers/skill_contribution_provider.dart';
import 'package:teampilot/services/session/session_lifecycle_service.dart';
import 'package:teampilot/services/team_generation/mcp/team_composer_mcp_constants.dart';
import 'package:teampilot/services/team_generation/providers/managed_team_builder_skill_provider.dart';
import 'package:teampilot/services/team_generation/providers/team_builder_skill_md.dart';

import '../../support/in_memory_filesystem.dart';
import '../../support/post_frame_test_harness.dart';

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  test(
    'resolver injects the managed builder skill only for builder sessions',
    () async {
      final builderSession = AppSession(
        sessionId: 'builder',
        workspaceId: 'ws',
        purpose: SessionPurpose.teamGeneration,
        workflowId: 'wf',
        createdAt: 1,
      );
      final normalSession = AppSession(
        sessionId: 'normal',
        workspaceId: 'ws',
        createdAt: 1,
      );

      final lifecycle = SessionLifecycleService(
        resourceProviderResolver:
            TeamGenerationGraph.resourceProvidersForSession,
      );
      final builderDefaults = lifecycle.resourceProvidersForSession(
        builderSession,
        ResourceProviderSet.empty,
      );
      final normalDefaults = lifecycle.resourceProvidersForSession(
        normalSession,
        ResourceProviderSet.empty,
      );

      expect(builderDefaults.skills, hasLength(1));
      expect(
        builderDefaults.skills.single.providerId,
        ManagedTeamBuilderSkillProvider.skillId,
      );
      expect(normalDefaults.skills, isEmpty);
      expect(resolveTeamGenerationSettingsSnapshot, isNotNull);
    },
  );

  test(
    'runtime composition materializes builder-only resources without leaking them to destination or ordinary sessions',
    () async {
      final builder = AppSession(
        sessionId: 'builder',
        workspaceId: 'ws',
        purpose: SessionPurpose.teamGeneration,
        workflowId: 'wf',
        createdAt: 1,
      );
      final destination = AppSession(
        sessionId: 'destination',
        workspaceId: 'ws',
        purpose: SessionPurpose.normal,
        sessionTeam: 'generated-team',
        createdAt: 1,
      );
      final ordinary = AppSession(
        sessionId: 'ordinary',
        workspaceId: 'ws',
        createdAt: 1,
      );
      final lifecycle = SessionLifecycleService(
        resourceProviderResolver:
            TeamGenerationGraph.resourceProvidersForSession,
      );
      final providers = lifecycle.resourceProvidersForSession(
        builder,
        ResourceProviderSet.empty,
      );
      final fs = InMemoryFilesystem();
      final contribution = (await providers.skills.single.provide(
        SkillProviderContext(
          cli: CliTool.claude,
          filesystem: fs,
          targetConfigDir: '/builder/config',
        ),
      )).single;
      final skillDirectory =
          (contribution.artifact! as SkillDirectoryArtifact).sourceDirectory;

      Map<String, Map<String, Object?>> compose(AppSession session) =>
          composeRuntimeExtraMcpServers(
            extra: const {},
            session: session,
            memberId: session.sessionId,
            cli: CliTool.claude,
            launchKind: RuntimeKind.local,
            cliRegistry: CliToolRegistry.builtIn(),
            catalogEndpoint: Uri.parse('http://127.0.0.1:4312/catalog/mcp'),
            composerEndpoint: Uri.parse(
              'http://127.0.0.1:4312/team-composer/mcp',
            ),
            teamGenerationTokenIssuer: (_) => 'workflow-token',
          );

      final builderMcp = compose(builder);
      final destinationMcp = compose(destination);
      final ordinaryMcp = compose(ordinary);

      expect(
        await fs.readString('$skillDirectory/SKILL.md'),
        teamBuilderSkillMd,
      );
      expect(contribution.origin.kind, ResourceOriginKind.managed);
      expect(builderMcp.keys, {
        catalogMcpServerName,
        TeamComposerMcpConstants.serverName,
      });
      expect(
        (builderMcp[TeamComposerMcpConstants.serverName]!['headers']
            as Map)[TeamComposerMcpConstants.tokenHeader],
        'workflow-token',
      );
      expect(destinationMcp, contains(catalogMcpServerName));
      expect(
        destinationMcp,
        isNot(contains(TeamComposerMcpConstants.serverName)),
      );
      expect(ordinaryMcp, contains(catalogMcpServerName));
      expect(ordinaryMcp, isNot(contains(TeamComposerMcpConstants.serverName)));
      expect(
        lifecycle
            .resourceProvidersForSession(destination, ResourceProviderSet.empty)
            .skills,
        isEmpty,
      );
      expect(
        lifecycle
            .resourceProvidersForSession(ordinary, ResourceProviderSet.empty)
            .skills,
        isEmpty,
      );
    },
  );
}
