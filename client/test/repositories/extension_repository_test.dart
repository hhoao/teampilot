import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/extension_manifest.dart';
import 'package:teampilot/repositories/extension_repository.dart';
import 'package:teampilot/services/extension/builtin_manifests.dart';

import '../support/in_memory_filesystem.dart';

ExtensionRepository _repo(
  InMemoryFilesystem fs, {
  List<ExtensionManifest>? manifests,
}) =>
    ExtensionRepository(
      fs: fs,
      stateFilePath: '/root/extensions/state.json',
      manifests: manifests ?? builtInExtensionManifests(),
    );

void main() {
  test('load returns empty state when file absent', () async {
    final repo = _repo(InMemoryFilesystem());
    final state = await repo.load();
    expect(state.globalEnabled, isEmpty);
    expect(state.installed, isEmpty);
  });

  test('setGlobalEnabled persists and reloads', () async {
    final fs = InMemoryFilesystem();
    final repo = _repo(fs);
    await repo.setGlobalEnabled('codegraph', true);

    final fresh = _repo(fs);
    expect((await fresh.load()).globalEnabled, contains('codegraph'));
  });

  test('effectiveEnabledIds applies override over global', () async {
    final fs = InMemoryFilesystem();
    final repo = _repo(fs);
    await repo.setGlobalEnabled('codegraph', true);
    await repo.setTeamOverride('team-a', 'codegraph', false);

    expect(await repo.effectiveEnabledIds('team-b'), contains('codegraph'));
    expect(await repo.effectiveEnabledIds('team-a'), isNot(contains('codegraph')));
  });

  test('recordInstalled / recordUninstalled persist', () async {
    final fs = InMemoryFilesystem();
    final repo = _repo(fs);
    await repo.recordInstalled('codegraph', '1.4.0');
    expect((await repo.load()).installed['codegraph']!.version, '1.4.0');
    await repo.recordUninstalled('codegraph');
    expect((await repo.load()).installed, isEmpty);
  });

  test('isEffectivelyEnabled reflects state', () async {
    final fs = InMemoryFilesystem();
    final repo = _repo(fs);
    expect(await repo.isEffectivelyEnabled('team-a', 'codegraph'), isFalse);
    await repo.setGlobalEnabled('codegraph', true);
    expect(await repo.isEffectivelyEnabled('team-a', 'codegraph'), isTrue);
  });
}
