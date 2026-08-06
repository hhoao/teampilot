import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/discoverable_member.dart';
import 'package:teampilot/models/discoverable_team.dart';
import 'package:teampilot/services/expert_hub/local_expert_store.dart';
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
      responsibilities: 'You are a PM.',
      playbook: 'Break work into milestones.',
    ),
  );
}

void main() {
  late InMemoryFilesystem fs;
  late LocalExpertStore store;

  setUp(() {
    fs = InMemoryFilesystem();
    final paths = AppPaths('/tp');
    store = LocalExpertStore(
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
    final first = await store.save(_sampleMember(key: 'local/existing-id'));
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

    final fresh = LocalExpertStore(
      fs: fs,
      dirOverride: AppPaths('/tp').memberHubLocalTemplatesDir,
    );
    expect(await fresh.loadAll(), [saved]);
  });

  test('putClone stores under the catalog key (nested path)', () async {
    final saved = await store.putClone(
      _sampleMember().copyWith(
        key: 'acme/experts/pm',
        source: ExpertMemberSource.clone,
        originTeamKey: 'acme/teams/squad',
        clonedAt: 1723000000000,
      ),
    );
    expect(saved.key, 'acme/experts/pm');

    final loaded = await store.getByKey('acme/experts/pm');
    expect(loaded, isNotNull);
    expect(loaded!.source, ExpertMemberSource.clone);
    expect(loaded.originTeamKey, 'acme/teams/squad');
    expect(loaded.clonedAt, 1723000000000);
  });

  test('getByKey reads any key (shadow lookup)', () async {
    await store.putClone(_sampleMember().copyWith(key: 'acme/experts/pm'));
    expect(await store.getByKey('acme/experts/pm'), isNotNull);
  });

  test('loadAll reads nested clone files', () async {
    await store.putClone(_sampleMember().copyWith(key: 'acme/experts/pm'));
    await store.save(_sampleMember());

    final loaded = await store.loadAll();
    expect(
      loaded.map((m) => m.key),
      containsAll(['acme/experts/pm', 'local/test-uuid']),
    );
  });

  test('migrateLegacyLayout purges old clones and keeps user-custom', () async {
    final ctx = fs.pathContext;
    final dir = AppPaths('/tp').memberHubLocalTemplatesDir;
    await fs.writeString(
      ctx.join(dir, 'old-clone.json'),
      jsonEncode({
        ..._sampleMember().toJson(),
        'catalogKey': 'acme/experts/pm', // legacy uuid-clone marker
      }),
    );
    await fs.writeString(
      ctx.join(dir, 'old-custom.json'),
      jsonEncode(
        _sampleMember().copyWith(key: 'local/old-custom').toJson(),
      ),
    );

    await store.migrateLegacyLayout();

    expect(await fs.readString(ctx.join(dir, 'old-clone.json')), isNull,
        reason: 'old uuid clone is purged');
    final relocated = await store.getByKey('local/old-custom');
    expect(relocated, isNotNull,
        reason: 'legacy user-custom is relocated under local/');
    expect(relocated!.name, 'Product Manager');
  });
}
