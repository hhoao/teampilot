import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/discoverable_team.dart';
import 'package:teampilot/models/mcp_server.dart';
import 'package:teampilot/models/plugin.dart';
import 'package:teampilot/models/skill.dart';
import 'package:teampilot/pages/expert_hub/expert_editor_deps.dart';

Skill _skill({
  required String id,
  required String name,
  String directory = 'skills/x',
  String? repoOwner,
  String? repoName,
  String? repoBranch,
}) => Skill(
  id: id,
  name: name,
  description: '',
  directory: directory,
  repoOwner: repoOwner,
  repoName: repoName,
  repoBranch: repoBranch,
  installedAt: 1,
  updatedAt: 1,
);

Plugin _plugin({
  required String id,
  required String name,
  String? marketplaceOwner,
  String? marketplaceName,
  String? marketplaceBranch,
}) => Plugin(
  id: id,
  name: name,
  description: '',
  version: '1.0.0',
  directory: 'dir',
  marketplaceOwner: marketplaceOwner,
  marketplaceName: marketplaceName,
  marketplaceBranch: marketplaceBranch,
  installedAt: 1,
  updatedAt: 1,
);

McpServer _mcp({required String id, required String name}) => McpServer(
  id: id,
  name: name,
  description: '',
  server: const {'type': 'stdio', 'command': 'echo'},
  enabled: true,
  updatedAt: 1,
);

void main() {
  test('portable skill/plugin/mcp become deps', () {
    final result = resolveExpertEditorDeps(
      selectedSkillIds: const ['obra/superpowers:brainstorming'],
      selectedPluginIds: const ['acme/market/entry'],
      selectedMcpIds: const ['mcp-1'],
      skills: [
        _skill(
          id: 'obra/superpowers:brainstorming',
          name: 'Brainstorming',
          directory: 'skills/brainstorming',
          repoOwner: 'obra',
          repoName: 'superpowers',
          repoBranch: 'main',
        ),
      ],
      plugins: [
        _plugin(
          id: 'acme/market/entry',
          name: 'Entry',
          marketplaceOwner: 'acme',
          marketplaceName: 'market',
          marketplaceBranch: 'main',
        ),
      ],
      mcps: [_mcp(id: 'mcp-1', name: 'Echo')],
    );

    expect(result.skillDeps, hasLength(1));
    expect(result.skillDeps.single.name, 'Brainstorming');
    expect(result.pluginDeps, hasLength(1));
    expect(result.pluginDeps.single.entryName, 'entry');
    expect(result.mcpDeps, hasLength(1));
    expect(result.mcpDeps.single.id, 'mcp-1');
    expect(result.skippedNonPortableIds, isEmpty);
  });

  test('non-portable skill is skipped unless already on expert', () {
    final existing = SkillDependencyRef(
      repoOwner: 'obra',
      repoName: 'superpowers',
      repoBranch: 'main',
      directory: 'skills/brainstorming',
      name: 'Brainstorming',
    );

    final skipped = resolveExpertEditorDeps(
      selectedSkillIds: const ['local-only'],
      selectedPluginIds: const [],
      selectedMcpIds: const [],
      skills: [_skill(id: 'local-only', name: 'Local')],
      plugins: const [],
      mcps: const [],
    );
    expect(skipped.skillDeps, isEmpty);
    expect(skipped.skippedNonPortableIds, ['local-only']);

    final kept = resolveExpertEditorDeps(
      selectedSkillIds: [existing.expectedLocalId],
      selectedPluginIds: const [],
      selectedMcpIds: const [],
      skills: const [],
      plugins: const [],
      mcps: const [],
      existingSkillDeps: [existing],
    );
    expect(kept.skillDeps, [existing]);
    expect(kept.skippedNonPortableIds, isEmpty);
  });

  test('selected id helpers mirror dep local ids', () {
    const skill = SkillDependencyRef(
      repoOwner: 'obra',
      repoName: 'superpowers',
      repoBranch: 'main',
      directory: 'skills/tdd',
      name: 'TDD',
    );
    const plugin = PluginDependencyRef(
      marketplaceOwner: 'acme',
      marketplaceName: 'market',
      marketplaceBranch: 'main',
      entryName: 'entry',
      name: 'Entry',
    );
    const mcp = McpDependencyRef(
      id: 'mcp-1',
      name: 'Echo',
      server: {'type': 'stdio'},
    );

    expect(expertEditorSelectedSkillIds([skill]), {skill.expectedLocalId});
    expect(expertEditorSelectedPluginIds([plugin]), {plugin.expectedLocalId});
    expect(expertEditorSelectedMcpIds([mcp]), {'mcp-1'});
  });
}
