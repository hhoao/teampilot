import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/repositories/extension_repository.dart';
import 'package:teampilot/services/extension/builtin_manifests.dart';
import 'package:teampilot/services/extension/extension_state_migration.dart';

import '../../support/in_memory_filesystem.dart';

ExtensionRepository _repo(InMemoryFilesystem fs) => ExtensionRepository(
      fs: fs,
      stateFilePath: '/root/extensions/state.json',
      manifests: builtInExtensionManifests(),
    );

void main() {
  test('migrates legacy rtk=true into globalEnabled exactly once', () async {
    final fs = InMemoryFilesystem();
    final repo = _repo(fs);

    await ExtensionStateMigration.run(repository: repo, legacyRtkEnabled: () async => true);
    expect((await repo.load(forceReload: true)).globalEnabled, contains('rtk'));

    await ExtensionStateMigration.run(repository: repo, legacyRtkEnabled: () async => false);
    expect((await repo.load(forceReload: true)).globalEnabled, contains('rtk'));
  });

  test('does not enable rtk when legacy flag was false', () async {
    final fs = InMemoryFilesystem();
    final repo = _repo(fs);
    await ExtensionStateMigration.run(repository: repo, legacyRtkEnabled: () async => false);
    expect((await repo.load(forceReload: true)).globalEnabled, isEmpty);
  });
}
