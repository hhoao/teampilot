import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/config_bundle.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/catalog/providers/catalog_prompt_provider.dart';
import 'package:teampilot/services/catalog/providers/managed_catalog_skill_provider.dart';
import 'package:teampilot/services/catalog/providers/teampilot_catalog_skill_md.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/resource/contribution/prompt_document.dart';
import 'package:teampilot/services/resource/contribution/resource_origin.dart';
import 'package:teampilot/services/resource/providers/prompt_contribution_provider.dart';
import 'package:teampilot/services/resource/providers/skill_contribution_provider.dart';
import 'package:teampilot/services/resource/resource_scope.dart';

const _catalogPromptSentence =
    'To install or manage TeamPilot skills, plugins, or MCP servers, load the teampilot-catalog skill and use the teampilot MCP. Do not install into ~/.claude.';

const _skillDescription =
    'Install, import, create, update, or remove TeamPilot skills, plugins, and MCP servers. Use when the user wants to add, install, find, or import a skill, plugin, or MCP; search skills.sh or a marketplace; run npx or an install script; or mentions superpowers, context7, or community agent skills. Never write to ~/.claude/skills, .claude/skills, or ~/.claude.json — those paths are wiped on the next TeamPilot session start.';

void main() {
  late Directory sourceDir;

  setUp(() {
    sourceDir = Directory.systemTemp.createTempSync('teampilot-catalog-skill_');
    File(p.join(sourceDir.path, 'SKILL.md')).writeAsStringSync('# fixture\n');
  });

  tearDown(() {
    if (sourceDir.existsSync()) sourceDir.deleteSync(recursive: true);
  });

  test('providerId is teampilot-catalog', () {
    expect(
      ManagedCatalogSkillProvider(sourceDirectory: sourceDir.path).providerId,
      'teampilot-catalog',
    );
  });

  test(
    'provide returns teampilot-catalog even when scope.skillIds is empty',
    () async {
      final provider = ManagedCatalogSkillProvider(
        sourceDirectory: sourceDir.path,
      );
      final contributions = [
        ...await provider.provide(
          const SkillProviderContext(
            cli: CliTool.claude,
            scope: SimpleResourceScope(bundle: ConfigBundle()),
          ),
        ),
      ];

      expect(contributions, hasLength(1));
      final skill = contributions.single;
      expect(skill.id, 'teampilot-catalog');
      expect(skill.invocationName, 'teampilot-catalog');
      expect(skill.origin.providerId, 'teampilot-catalog');
      expect(skill.origin.kind, ResourceOriginKind.managed);
      expect(skill.artifact, isA<SkillDirectoryArtifact>());
      expect(
        (skill.artifact! as SkillDirectoryArtifact).sourceDirectory,
        sourceDir.path,
      );
    },
  );

  test(
    'provide without sourceDirectory writes SKILL.md onto the session filesystem',
    () async {
      final fs = LocalFilesystem();
      final root = Directory.systemTemp.createTempSync(
        'teampilot-catalog-managed_',
      );
      addTearDown(() {
        if (root.existsSync()) root.deleteSync(recursive: true);
      });
      final targetConfigDir = p.join(root.path, 'cfg', 'claude');
      await fs.ensureDir(targetConfigDir);

      final contributions = [
        ...await ManagedCatalogSkillProvider().provide(
          SkillProviderContext(
            cli: CliTool.claude,
            scope: const SimpleResourceScope(bundle: ConfigBundle()),
            filesystem: fs,
            targetConfigDir: targetConfigDir,
          ),
        ),
      ];

      expect(contributions, hasLength(1));
      final artifact = contributions.single.artifact! as SkillDirectoryArtifact;
      final expectedDir = p.join(
        targetConfigDir,
        '.teampilot-managed',
        'teampilot-catalog',
      );
      expect(artifact.sourceDirectory, expectedDir);
      final skillMd = p.join(expectedDir, 'SKILL.md');
      expect((await fs.stat(skillMd)).isFile, isTrue);
      expect(await fs.readString(skillMd), contains(_skillDescription));
    },
  );

  test(
    'provide ignores catalog skillIds and still returns one contribution',
    () async {
      final provider = ManagedCatalogSkillProvider(
        sourceDirectory: sourceDir.path,
      );
      final contributions = [
        ...await provider.provide(
          const SkillProviderContext(
            cli: CliTool.codex,
            scope: SimpleResourceScope(
              bundle: ConfigBundle(skillIds: ['other', 'also-other']),
            ),
          ),
        ),
      ];

      expect(contributions.map((skill) => skill.id), ['teampilot-catalog']);
    },
  );

  test(
    'CatalogPromptProvider content points at teampilot-catalog and teampilot MCP',
    () async {
      final contributions = [
        ...await const CatalogPromptProvider().provide(
          PromptProviderContext(cli: CliTool.claude),
        ),
      ];

      expect(contributions, hasLength(1));
      final prompt = contributions.single;
      expect(prompt.content, _catalogPromptSentence);
      expect(prompt.content, contains('teampilot-catalog'));
      expect(prompt.content, contains('teampilot MCP'));
      expect(prompt.mergeRole, PromptMergeRole.append);
      expect(prompt.origin.kind, ResourceOriginKind.managed);
    },
  );

  test('shipped SKILL.md description matches spec trigger wording', () {
    final skillMd = File(
      p.join(
        'lib',
        'services',
        'catalog',
        'managed_skills',
        'teampilot-catalog',
        'SKILL.md',
      ),
    );
    expect(skillMd.existsSync(), isTrue);
    final text = skillMd.readAsStringSync();
    expect(
      text.replaceAll('\r\n', '\n'),
      contains('description: $_skillDescription'),
    );
    expect(text, contains('search_'));
    expect(text, contains('install_'));
    expect(text, contains('import_'));
    expect(text, contains('~/.claude'));
    expect(
      teampilotCatalogSkillMd.replaceAll('\r\n', '\n'),
      text.replaceAll('\r\n', '\n'),
    );
  });
}
