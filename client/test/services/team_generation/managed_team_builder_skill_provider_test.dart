import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/app/team_generation_graph.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/catalog/catalog_mcp_constants.dart';
import 'package:teampilot/services/catalog/catalog_mcp_transport.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/resource/contribution/resource_origin.dart';
import 'package:teampilot/services/resource/resource_provider_set.dart';
import 'package:teampilot/services/resource/providers/skill_contribution_provider.dart';
import 'package:teampilot/services/team_generation/mcp/team_composer_mcp_constants.dart';
import 'package:teampilot/services/team_generation/mcp/team_composer_mcp_transport.dart';
import 'package:teampilot/services/team_generation/providers/managed_team_builder_skill_provider.dart';
import 'package:teampilot/services/team_generation/providers/team_builder_skill_md.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  test(
    'managed builder skill source and materialized mirror are identical',
    () async {
      final provider = ManagedTeamBuilderSkillProvider();
      final resource = await provider.resolve(
        ManagedTeamBuilderSkillProvider.skillId,
      );

      final mirror = await File(
        'lib/services/team_generation/managed_skills/team-builder/SKILL.md',
      ).readAsString();

      expect(resource, isNotNull);
      expect(resource!.content, teamBuilderSkillMd);
      expect(mirror, teamBuilderSkillMd);
      for (final marker in const [
        'get_generation_context',
        'probe_workspace_targets',
        'validate_team_plan',
        'finalize_team_generation',
        '2–5',
        'team-lead',
        'Catalog MCP',
        'Team Composer MCP',
        'Never invent Catalog resource IDs.',
        'Never edit TeamPilot JSON manifests',
        'inputs, outputs, launch configuration, and required resources',
        'After `finalize_team_generation` is accepted, **stop**',
        'implement the original task',
        'MCP failures are ordinary tool errors',
      ]) {
        expect(mirror, contains(marker));
      }
      expect(mirror, isNot(contains('TeamCreate')));
    },
  );

  test(
    'provider supplies skill contribution with directory artifact',
    () async {
      final fs = InMemoryFilesystem();
      const targetConfigDir = '/session/config';
      final provider = ManagedTeamBuilderSkillProvider();
      final contributions = await provider.provide(
        SkillProviderContext(
          cli: CliTool.claude,
          filesystem: fs,
          targetConfigDir: targetConfigDir,
        ),
      );

      final contribution = contributions.single;
      expect(contribution.id, ManagedTeamBuilderSkillProvider.skillId);
      expect(contribution.origin.kind, ResourceOriginKind.managed);
      expect(contribution.artifact, isA<SkillDirectoryArtifact>());

      final dir =
          (contribution.artifact! as SkillDirectoryArtifact).sourceDirectory;
      final written = await fs.readString('$dir/SKILL.md');
      expect(written, teamBuilderSkillMd);
      expect(dir, contains('.teampilot-managed'));
    },
  );

  test('resolve returns null for unrelated skill ids', () async {
    final provider = ManagedTeamBuilderSkillProvider();
    expect(await provider.resolve('some-other-skill'), isNull);
    expect(
      await provider.resolve(ManagedTeamBuilderSkillProvider.skillId),
      isNotNull,
    );
  });

  test(
    'builder runtime materializes its managed skill and both MCPs without leaking the skill to a destination',
    () async {
      final fs = InMemoryFilesystem();
      final builder = AppSession(
        sessionId: 'builder-session',
        workspaceId: 'ws',
        purpose: SessionPurpose.teamGeneration,
        workflowId: 'wf',
        createdAt: 1,
      );
      final destination = AppSession(
        sessionId: 'destination-session',
        workspaceId: 'ws',
        purpose: SessionPurpose.normal,
        sessionTeam: 'generated-team',
        createdAt: 1,
      );

      final builderProviders = TeamGenerationGraph.resourceProvidersForSession(
        builder,
        ResourceProviderSet.empty,
      );
      final destinationProviders =
          TeamGenerationGraph.resourceProvidersForSession(
            destination,
            ResourceProviderSet.empty,
          );
      final contribution = (await builderProviders.skills.single.provide(
        SkillProviderContext(
          cli: CliTool.claude,
          filesystem: fs,
          targetConfigDir: '/builder/config',
        ),
      )).single;
      final skillDirectory =
          (contribution.artifact! as SkillDirectoryArtifact).sourceDirectory;

      final registry = CliToolRegistry.builtIn();
      final runtimeMcp = withCatalogMcpServer(
        extra: {
          TeamComposerMcpConstants.serverName:
              resolveTeamComposerMcpTransportConfig(
                cliRegistry: registry,
                composerEndpoint: teamComposerMcpEndpointForPort(4312),
                sessionId: builder.sessionId,
                memberId: builder.sessionId,
                cli: CliTool.claude,
                workflowToken: 'workflow-token',
                bridgeLocator: () => null,
              ),
        },
        catalogConfig: resolveCatalogMcpTransportConfig(
          cliRegistry: registry,
          catalogEndpoint: Uri.parse('http://127.0.0.1:4312/catalog/mcp'),
          sessionId: builder.sessionId,
          memberId: builder.sessionId,
          cli: CliTool.claude,
          teamGenerationToken: 'catalog-token',
          bridgeLocator: () => null,
        ),
      );

      expect(
        await fs.readString('$skillDirectory/SKILL.md'),
        teamBuilderSkillMd,
      );
      expect(runtimeMcp.keys, {
        catalogMcpServerName,
        TeamComposerMcpConstants.serverName,
      });
      expect(
        runtimeMcp[catalogMcpServerName]!['url'],
        'http://127.0.0.1:4312/catalog/mcp',
      );
      expect(
        (runtimeMcp[TeamComposerMcpConstants.serverName]!['headers']
            as Map)[TeamComposerMcpConstants.tokenHeader],
        'workflow-token',
      );
      expect(destinationProviders.skills, isEmpty);
      expect(
        destinationProviders.skills.map((provider) => provider.providerId),
        isNot(contains(ManagedTeamBuilderSkillProvider.skillId)),
      );
    },
  );
}
