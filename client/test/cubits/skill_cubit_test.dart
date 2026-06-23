import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/skill_cubit.dart';
import 'package:teampilot/models/skill.dart';
import 'package:teampilot/repositories/skill_repository.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/storage/runtime_context.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('skill-cubit-');
    final paths = AppPaths(tmp.path);
    AppStorage.installForTesting(
      filesystem: LocalFilesystem(
        pathContext: AppPaths.pathContextForDataRoot(paths.basePath),
      ),
      paths: paths,
      home: tmp.path,
      cwd: tmp.path,
    );
  });

  tearDown(() {
    AppStorage.resetForTesting();
    tmp.deleteSync(recursive: true);
  });

  test('loadAll() populates installed + repos without discovery sync', () async {
    final cubit = SkillCubit(SkillRepository());
    await cubit.loadAll();
    expect(cubit.state.status, SkillLoadStatus.ready);
    expect(cubit.state.repos, isNotEmpty);
    expect(cubit.state.installed, isEmpty);
    expect(cubit.state.discoverable, isEmpty);
    expect(cubit.state.discoveryLoading, isFalse);
    expect(cubit.state.repoSyncingKeys, isEmpty);
  });

  test('ensureDiscoveryLoaded does not re-sync when list is populated', () async {
    final cubit = SkillCubit(SkillRepository());
    cubit.emit(
      cubit.state.copyWith(
        discoverable: const [
          DiscoverableSkill(
            key: 'a:b:c',
            name: 'c',
            description: '',
            directory: 'c',
            repoOwner: 'o',
            repoName: 'n',
            repoBranch: 'main',
          ),
        ],
      ),
    );
    await cubit.ensureDiscoveryLoaded();
    expect(cubit.state.discoveryLoading, isFalse);
    expect(cubit.state.repoSyncingKeys, isEmpty);
  });
}
