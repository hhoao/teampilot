import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/project_profile.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/project_profile_repository.dart';

void main() {
  test('save and load round-trip', () async {
    final tmp = await Directory.systemTemp.createTemp('fs_project_profile_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final repo = ProjectProfileRepository(rootDir: tmp.path);
    const profile = ProjectProfile(
      projectId: 'p1',
      cli: CliTool.claude,
      agent: ProjectAgentConfig(model: 'sonnet'),
      updatedAt: 1,
    );
    await repo.save(profile);
    final loaded = await repo.load('p1');
    expect(loaded?.cli, CliTool.claude);
    expect(loaded?.agent.model, 'sonnet');
    expect(loaded?.updatedAt, 1);
  });

  test('createDefault seeds claude and empty resource lists', () async {
    final tmp = await Directory.systemTemp.createTemp('fs_project_profile_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final repo = ProjectProfileRepository(rootDir: tmp.path);
    final profile = await repo.createDefault('p-new');
    expect(profile.projectId, 'p-new');
    expect(profile.skillIds, isEmpty);
    expect(profile.pluginIds, isEmpty);
    expect(profile.mcpServerIds, isEmpty);
    expect(profile.providerIdsByTool, isEmpty);
    expect(profile.cli, CliTool.claude);
  });

  test('load returns null when profile file is missing', () async {
    final tmp = await Directory.systemTemp.createTemp('fs_project_profile_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final repo = ProjectProfileRepository(rootDir: tmp.path);
    expect(await repo.load('missing'), isNull);
  });

  test('loadOrCreate persists default when missing', () async {
    final tmp = await Directory.systemTemp.createTemp('fs_project_profile_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final repo = ProjectProfileRepository(rootDir: tmp.path);
    final profile = await repo.loadOrCreate('p-or-create');
    expect(profile.projectId, 'p-or-create');
    expect(profile.cli, CliTool.claude);

    final reloaded = await repo.load('p-or-create');
    expect(reloaded, profile);
  });
}
