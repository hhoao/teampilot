import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/config_bundle.dart';
import 'package:teampilot/models/plugin.dart';
import 'package:teampilot/models/skill.dart';
import 'package:teampilot/services/cli/codex/capabilities/skill.dart';
import 'package:teampilot/services/cli/opencode/capabilities/skill.dart';
import 'package:teampilot/services/cli/registry/capabilities/skill_capability.dart';
import 'package:teampilot/services/cli/registry/capabilities/native_command_capability.dart';
import 'package:teampilot/services/compose/compose_slash_catalog.dart';

void main() {
  const codexSyntax = CodexSkillCapability();
  const opencodeSyntax = OpencodeSkillCapability();

  final standaloneSkill = Skill(
    id: 'local:using-git-worktrees',
    name: 'Using Git Worktrees',
    description: '',
    directory: 'using-git-worktrees',
    installedAt: 0,
    updatedAt: 0,
  );

  final superpowers = Plugin(
    id: 'superpowers',
    name: 'superpowers',
    description: '',
    version: '1.0',
    directory: 'superpowers',
    installedAt: 0,
    updatedAt: 0,
    capabilities: const PluginCapabilities(
      skills: [PluginSkillRef(name: 'using-git-worktrees')],
      commands: [PluginCommand(name: 'review')],
    ),
  );

  const bundle = ConfigBundle(
    skillIds: ['local:using-git-worktrees'],
    pluginIds: ['superpowers'],
  );

  List<ComposeSlashCandidate> build({
    required List<Skill> skills,
    required List<Plugin> plugins,
    SkillCapability? syntax,
  }) => buildComposeSlashCandidates(
    skills: skills,
    plugins: plugins,
    enabledBundle: bundle,
    query: '',
    syntax: syntax,
  );

  test('default syntax inserts /name for standalone and plugin skills', () {
    final candidates = build(skills: [standaloneSkill], plugins: [superpowers]);
    expect(
      candidates
          .where((c) => c.kind == ComposeSlashCandidateKind.skill)
          .map((c) => c.insertText),
      contains('/using-git-worktrees'),
    );
  });

  test(r'codex syntax inserts $name for standalone skills', () {
    final candidates = build(
      skills: [standaloneSkill],
      plugins: const [],
      syntax: codexSyntax,
    );
    final skillCandidates = candidates
        .where((c) => c.kind == ComposeSlashCandidateKind.skill)
        .map((c) => c.insertText);
    expect(skillCandidates, contains(r'$using-git-worktrees'));
  });

  test(r'codex syntax inserts namespaced $plugin:name for plugin skills', () {
    final candidates = build(
      skills: const [],
      plugins: [superpowers],
      syntax: codexSyntax,
    );
    final skillCandidates = candidates
        .where((c) => c.kind == ComposeSlashCandidateKind.skill)
        .map((c) => c.insertText);
    expect(skillCandidates, contains(r'$superpowers:using-git-worktrees'));
  });

  test('opencode syntax prepends a space before /', () {
    final candidates = build(
      skills: [standaloneSkill],
      plugins: const [],
      syntax: opencodeSyntax,
    );
    expect(
      candidates
          .where((c) => c.kind == ComposeSlashCandidateKind.skill)
          .map((c) => c.insertText),
      contains(' /using-git-worktrees'),
    );
  });

  test('plugin commands keep the slash form regardless of skill syntax', () {
    final candidates = build(
      skills: const [],
      plugins: [superpowers],
      syntax: codexSyntax,
    );
    final commandCandidates = candidates
        .where((c) => c.kind == ComposeSlashCandidateKind.command)
        .map((c) => c.insertText);
    expect(commandCandidates, contains('/review'));
  });

  test('merges native commands before plugin commands and keeps syntax', () {
    final candidates = buildComposeSlashCandidates(
      skills: [standaloneSkill],
      plugins: [superpowers],
      enabledBundle: bundle,
      query: '',
      syntax: codexSyntax,
      nativeCommands: const [
        NativeCommand(
          name: 'goal',
          description: NativeCommandDescription.goal,
          argumentHint: '<objective>',
        ),
        NativeCommand(name: 'help', description: NativeCommandDescription.help),
      ],
    );

    expect(candidates.map((item) => item.insertText), [
      r'$using-git-worktrees',
      r'$superpowers:using-git-worktrees',
      '/goal ',
      '/help',
      '/review',
    ]);
    expect(candidates[2].source, ComposeSlashCandidateSource.native);
    expect(candidates[2].insertion.suffix, isEmpty);
    expect(candidates[3].insertion.suffix, isEmpty);
    expect(candidates[4].source, ComposeSlashCandidateSource.plugin);
    expect(candidates[4].insertion.suffix, ' ');
  });

  test('filters native commands by meaningful description search terms', () {
    const commands = [
      NativeCommand(name: 'goal', description: NativeCommandDescription.goal),
      NativeCommand(
        name: 'compact',
        description: NativeCommandDescription.compact,
      ),
      NativeCommand(name: 'plan', description: NativeCommandDescription.plan),
    ];

    String matchFor(String query) => buildComposeSlashCandidates(
      skills: const [],
      plugins: const [],
      enabledBundle: const ConfigBundle(),
      query: query,
      nativeCommands: commands,
    ).single.insertText;

    expect(matchFor('durable'), '/goal');
    expect(matchFor('context'), '/compact');
    expect(matchFor('workflow'), '/plan');
  });

  for (final query in ['', 'workflow']) {
    test(
      'keeps native and plugin commands discoverable with 20 matching skills '
      'for query "$query"',
      () {
        final skills = List.generate(
          20,
          (index) => Skill(
            id: 'skill-$index',
            name: 'Workflow Skill $index',
            description: '',
            directory: 'workflow-skill-$index',
            installedAt: 0,
            updatedAt: 0,
          ),
        );
        final plugin = Plugin(
          id: 'workflow-plugin',
          name: 'Workflow Plugin',
          description: '',
          version: '1.0',
          directory: 'workflow-plugin',
          installedAt: 0,
          updatedAt: 0,
          capabilities: const PluginCapabilities(
            commands: [PluginCommand(name: 'workflow-review')],
          ),
        );
        final candidates = buildComposeSlashCandidates(
          skills: skills,
          plugins: [plugin],
          enabledBundle: ConfigBundle(
            skillIds: skills.map((skill) => skill.id).toList(),
            pluginIds: const ['workflow-plugin'],
          ),
          query: query,
          nativeCommands: const [
            NativeCommand(
              name: 'plan',
              description: NativeCommandDescription.plan,
            ),
          ],
        );

        expect(candidates, hasLength(20));
        expect(
          candidates
              .where(
                (candidate) =>
                    candidate.kind == ComposeSlashCandidateKind.skill,
              )
              .length,
          lessThan(20),
        );
        expect(
          candidates.map((candidate) => candidate.insertText),
          contains('/plan'),
        );
        expect(
          candidates.map((candidate) => candidate.insertText),
          contains('/workflow-review'),
        );
      },
    );
  }
}
