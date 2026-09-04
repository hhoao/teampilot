import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/resource/contribution/resource_origin.dart';
import 'package:teampilot/services/resource/providers/skill_contribution_provider.dart';
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

      // git checkout on Windows converts the mirror to CRLF; compare LF-normalized.
      final mirror = (await File(
        'lib/services/team_generation/managed_skills/team-builder/SKILL.md',
      ).readAsString()).replaceAll('\r\n', '\n');

      expect(resource, isNotNull);
      expect(resource!.content.replaceAll('\r\n', '\n'), teamBuilderSkillMd);
      expect(mirror, teamBuilderSkillMd);
      for (final marker in const [
        'get_generation_context',
        'probe_workspace_targets',
        'validate_team_plan',
        'finalize_team_generation',
        '2–5',
        'team-lead',
        'planSchema',
        'requestedMode',
        'Catalog MCP',
        'Team Composer MCP',
        'Never invent Catalog resource IDs.',
        'Never edit TeamPilot JSON manifests',
        'Do **not** probe the schema with empty or partial plans',
        'Prefer ≤3 validate rounds',
        'After `finalize_team_generation` is accepted, **stop**',
        'implement the original task',
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
}
