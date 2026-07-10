import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/discoverable_member.dart';
import 'package:teampilot/models/discoverable_team.dart';
import 'package:teampilot/services/expert_hub/local_member_template_store.dart';
import 'package:teampilot/services/storage/app_storage.dart';

import '../../support/in_memory_filesystem.dart';

DiscoverableMember _sampleMember({String key = 'owner/repo/pm'}) {
  return DiscoverableMember(
    key: key,
    name: 'Product Manager',
    description: 'Plans and prioritizes work.',
    category: 'Business',
    source: ExpertMemberSource.registry,
    member: const DiscoverableTeamMember(
      name: 'pm',
      prompt: 'You are a PM.',
      playbook: 'Break work into milestones.',
    ),
  );
}

void main() {
  late InMemoryFilesystem fs;
  late LocalMemberTemplateStore store;

  setUp(() {
    fs = InMemoryFilesystem();
    final paths = AppPaths('/tp');
    store = LocalMemberTemplateStore(
      fs: fs,
      dirOverride: paths.memberHubLocalTemplatesDir,
      uuidFactory: () => 'test-uuid',
    );
  });

  test('save assigns local key and source for non-local members', () async {
    final saved = await store.save(_sampleMember());

    expect(saved.key, 'local/test-uuid');
    expect(saved.source, ExpertMemberSource.local);
    expect(await store.getByKey('local/test-uuid'), saved);
  });

  test('save overwrites existing local key', () async {
    final first = await store.save(
      _sampleMember(key: 'local/existing-id'),
    );
    final updated = await store.save(
      first.copyWith(description: 'Updated description'),
    );

    expect(updated.key, 'local/existing-id');
    expect(updated.description, 'Updated description');
    expect(await store.loadAll(), [updated]);
  });

  test('loadAll reads all templates and skips invalid files', () async {
    await store.save(_sampleMember(key: 'local/a'));
    await store.save(_sampleMember(key: 'local/b').copyWith(name: 'Designer'));

    final ctx = fs.pathContext;
    await fs.writeString(
      ctx.join(AppPaths('/tp').memberHubLocalTemplatesDir, 'broken.json'),
      '{not json',
    );

    final loaded = await store.loadAll();
    expect(loaded.map((m) => m.key), containsAll(['local/a', 'local/b']));
    expect(loaded.length, 2);
  });

  test('delete removes local templates only', () async {
    await store.save(_sampleMember(key: 'local/to-delete'));
    await store.save(_sampleMember(key: 'local/to-keep'));

    await store.delete('local/to-delete');
    await store.delete('teampilot/builtin/developer');

    expect(await store.getByKey('local/to-delete'), isNull);
    expect(await store.getByKey('local/to-keep'), isNotNull);
  });

  test('save preserves pluginDeps and mcpDeps', () async {
    final saved = await store.save(
      _sampleMember().copyWith(
        pluginDeps: const [
          PluginDependencyRef(
            marketplaceOwner: 'acme',
            marketplaceName: 'tools',
            marketplaceBranch: 'main',
            entryName: 'lint',
            name: 'Lint',
          ),
        ],
        mcpDeps: const [
          McpDependencyRef(
            id: 'mcp-fs',
            name: 'Filesystem',
            description: 'fs',
            server: {'command': 'npx'},
          ),
        ],
      ),
    );

    expect(saved.pluginDeps.single.entryName, 'lint');
    expect(saved.mcpDeps.single.id, 'mcp-fs');
    expect(await store.getByKey(saved.key), saved);
  });

  test('persists across store instances', () async {
    final saved = await store.save(_sampleMember());

    final fresh = LocalMemberTemplateStore(
      fs: fs,
      dirOverride: AppPaths('/tp').memberHubLocalTemplatesDir,
    );
    expect(await fresh.loadAll(), [saved]);
  });
}

extension on DiscoverableMember {
  DiscoverableMember copyWith({
    String? key,
    String? name,
    String? description,
    String? category,
    ExpertMemberSource? source,
    DiscoverableTeamMember? member,
    List<SkillDependencyRef>? skillDeps,
    List<PluginDependencyRef>? pluginDeps,
    List<McpDependencyRef>? mcpDeps,
  }) {
    return DiscoverableMember(
      key: key ?? this.key,
      name: name ?? this.name,
      description: description ?? this.description,
      category: category ?? this.category,
      author: author,
      updatedAt: updatedAt,
      tags: tags,
      member: member ?? this.member,
      skillDeps: skillDeps ?? this.skillDeps,
      pluginDeps: pluginDeps ?? this.pluginDeps,
      mcpDeps: mcpDeps ?? this.mcpDeps,
      source: source ?? this.source,
      originTeamKey: originTeamKey,
    );
  }
}
