import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/skill/skill_pack_install_store.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  late InMemoryFilesystem fs;
  late SkillPackInstallStore store;

  setUp(() {
    fs = InMemoryFilesystem();
    store = SkillPackInstallStore(fs: fs, rootOverride: '/packs');
  });

  test('record round-trip preserves syncRoot and envExports', () async {
    final record = SkillPackInstallRecord(
      packId: 'owner/pack',
      skillIds: const ['owner/pack:review'],
      pathExports: const ['/sync/bin'],
      envExports: const {'GSTACK_BIN': '/sync/bin', 'FOO': 'bar'},
      installedAt: 42,
      syncRoot: '/sync',
    );
    await store.save(record);

    final loaded = await store.load('owner/pack');
    expect(loaded, isNotNull);
    expect(loaded!.packId, 'owner/pack');
    expect(loaded.skillIds, ['owner/pack:review']);
    expect(loaded.pathExports, ['/sync/bin']);
    expect(loaded.envExports, {'GSTACK_BIN': '/sync/bin', 'FOO': 'bar'});
    expect(loaded.installedAt, 42);
    expect(loaded.syncRoot, '/sync');
    expect(loaded.toJson().containsKey('packBin'), isFalse);
  });

  test('pathExportsForSkills dedupes and envExportsForSkills is first-wins',
      () async {
    await store.save(
      const SkillPackInstallRecord(
        packId: 'a/pack',
        skillIds: ['skill-a', 'shared'],
        pathExports: ['/a/bin', '/shared/bin'],
        envExports: {'X': 'from-a', 'ONLY_A': '1'},
        installedAt: 1,
        syncRoot: '/a',
      ),
    );
    await store.save(
      const SkillPackInstallRecord(
        packId: 'b/pack',
        skillIds: ['skill-b', 'shared'],
        pathExports: ['/b/bin', '/shared/bin'],
        envExports: {'X': 'from-b', 'ONLY_B': '2'},
        installedAt: 2,
        syncRoot: '/b',
      ),
    );

    final paths = await store.pathExportsForSkills(['shared']);
    expect(paths, ['/a/bin', '/shared/bin', '/b/bin']);

    final env = await store.envExportsForSkills(['shared']);
    expect(env['X'], 'from-a');
    expect(env['ONLY_A'], '1');
    expect(env['ONLY_B'], '2');
  });

  test('prependPath puts pack paths first', () {
    final env = SkillPackInstallStore.prependPath(
      {'PATH': '/usr/bin', 'KEEP': 'yes'},
      ['/pack/bin', '/other/bin'],
      isWindows: false,
    );
    expect(env['PATH'], '/pack/bin:/other/bin:/usr/bin');
    expect(env['KEEP'], 'yes');
  });

  test('mergeEnvExports applies non-empty pack values only', () {
    final env = SkillPackInstallStore.mergeEnvExports(
      {'KEEP': 'yes', 'X': 'old'},
      {'X': 'new', 'Y': 'y', 'EMPTY': ''},
    );
    expect(env, {'KEEP': 'yes', 'X': 'new', 'Y': 'y'});
  });
}
