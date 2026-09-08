import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/cli/codex/capabilities/skill.dart';
import 'package:teampilot/services/cli/cursor/capabilities/skill.dart';
import 'package:teampilot/services/cli/registry/capabilities/skill_capability.dart';
import 'package:teampilot/services/cli/registry/resources/default_resource_capability.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/resource/contribution/resource_origin.dart';
import 'package:teampilot/services/resource/providers/skill_contribution_provider.dart';

void main() {
  test('claude-family leaves plugin skills out of skills/', () async {
    final names = await _linkedNames(const DefaultSkillCapability());
    expect(names, ['catalog-skill']);
    expect(names, isNot(contains('superpowers--using-git-worktrees')));
  });

  test('cursor leaves plugin skills out of skills-cursor/', () async {
    final names = await _linkedNames(const CursorSkillCapability());
    expect(names, ['catalog-skill']);
  });

  test('cursor invokes plugin skills as /name without a plugin prefix', () {
    const cap = CursorSkillCapability();
    expect(
      cap.skillInvocationText('using-git-worktrees'),
      '/using-git-worktrees',
    );
    expect(
      cap.skillInvocationText('using-git-worktrees', namespace: 'superpowers'),
      '/using-git-worktrees',
    );
  });

  test('codex still links plugin skills under a -- directory name', () async {
    final names = await _linkedNames(const CodexSkillCapability());
    expect(
      names,
      containsAll(['catalog-skill', 'superpowers--using-git-worktrees']),
    );
  });

  test('claude reconcile removes stale plugin--skill links', () async {
    final fs = LocalFilesystem(pathContext: p.context);
    final tmp = await fs.createTempDir(prefix: 'skill_mat_stale_');
    final catalogSrc = fs.pathContext.join(tmp, 'catalog-skill');
    final pluginSrc = fs.pathContext.join(tmp, 'plugin-skill');
    await fs.ensureDir(catalogSrc);
    await fs.ensureDir(pluginSrc);
    final configDir = fs.pathContext.join(tmp, 'cfg');
    await fs.ensureDir(
      fs.pathContext.join(
        configDir,
        'skills',
        'superpowers--using-git-worktrees',
      ),
    );

    await const DefaultSkillCapability().materializeSkills(
      fs: fs,
      configDir: configDir,
      contributions: [_catalog(catalogSrc), _plugin(pluginSrc)],
    );

    final listed = await fs.listDir(fs.pathContext.join(configDir, 'skills'));
    expect(listed.map((e) => e.name), ['catalog-skill']);
    await fs.removeRecursive(tmp);
  });
}

SkillContribution _catalog(String sourceDir) => SkillContribution(
  id: 'catalog-skill',
  invocationName: 'catalog-skill',
  artifact: SkillDirectoryArtifact(sourceDir),
  origin: const ContributionOrigin(
    providerId: 'catalog',
    kind: ResourceOriginKind.catalog,
    sourceId: 'catalog-skill',
  ),
);

SkillContribution _plugin(String sourceDir) => SkillContribution(
  id: 'superpowers:using-git-worktrees',
  invocationName: 'using-git-worktrees',
  namespace: 'superpowers',
  artifact: SkillDirectoryArtifact(sourceDir),
  origin: const ContributionOrigin(
    providerId: 'plugin',
    kind: ResourceOriginKind.plugin,
    sourceId: 'superpowers:using-git-worktrees',
  ),
);

Future<List<String>> _linkedNames(SkillCapability cap) async {
  final fs = LocalFilesystem(pathContext: p.context);
  final tmp = await fs.createTempDir(prefix: 'skill_mat_');
  final catalogSrc = fs.pathContext.join(tmp, 'catalog-skill');
  final pluginSrc = fs.pathContext.join(tmp, 'plugin-skill');
  await fs.ensureDir(catalogSrc);
  await fs.ensureDir(pluginSrc);
  final configDir = fs.pathContext.join(tmp, 'cfg');

  await cap.materializeSkills(
    fs: fs,
    configDir: configDir,
    contributions: [_catalog(catalogSrc), _plugin(pluginSrc)],
  );

  final listed = await fs.listDir(
    fs.pathContext.join(configDir, cap.skillsSubdir),
  );
  await fs.removeRecursive(tmp);
  return listed.map((e) => e.name).toList()..sort();
}
