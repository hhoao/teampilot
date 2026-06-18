import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/config_bundle.dart';
import 'package:teampilot/models/personal_profile.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/launch_profile.dart';
import 'package:teampilot/repositories/launch_profile_repository.dart';

import '../support/post_frame_test_harness.dart';

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  late Directory tmp;
  late LaunchProfileRepository repo;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('identity_repo_');
    repo = LaunchProfileRepository(rootDir: tmp.path);
  });
  tearDown(() => tmp.delete(recursive: true));

  test('saves and loads both kinds', () async {
    await repo.save(const PersonalProfile(
      id: 'coding',
      display: 'Coding',
      bundle: const ConfigBundle(skillIds: ['s']),
    ));
    await repo.save(const TeamProfile(id: 'squad', name: 'Squad'));

    final all = await repo.loadAll();
    expect(all.map((e) => e.id).toSet(), {'coding', 'squad'});
    expect(all.whereType<PersonalProfile>().single.bundle.skillIds, ['s']);
    expect(all.whereType<TeamProfile>().single.display, 'Squad');
  });

  test('delete removes the identity dir', () async {
    await repo.save(const PersonalProfile(id: 'coding', display: 'Coding'));
    await repo.delete('coding');
    expect(await repo.loadAll(), isEmpty);
  });

  test('sorts personals by sortOrder when any has a custom order', () async {
    await repo.save(const PersonalProfile(
      id: 'b',
      display: 'B',
      sortOrder: 2,
    ));
    await repo.save(const PersonalProfile(
      id: 'a',
      display: 'A',
      sortOrder: 1,
    ));

    final personals = await repo.loadPersonalProfiles();
    expect(personals.map((p) => p.id).toList(), ['a', 'b']);
  });
}
