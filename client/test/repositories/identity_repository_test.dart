import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/config_bundle.dart';
import 'package:teampilot/models/personal_identity.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/identity.dart';
import 'package:teampilot/repositories/identity_repository.dart';

import '../support/post_frame_test_harness.dart';

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  late Directory tmp;
  late IdentityRepository repo;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('identity_repo_');
    repo = IdentityRepository(rootDir: tmp.path);
  });
  tearDown(() => tmp.delete(recursive: true));

  test('saves and loads both kinds', () async {
    await repo.save(const PersonalIdentity(
      id: 'coding',
      display: 'Coding',
      bundle: const ConfigBundle(skillIds: ['s']),
    ));
    await repo.save(const TeamIdentity(id: 'squad', name: 'Squad'));

    final all = await repo.loadAll();
    expect(all.map((e) => e.id).toSet(), {'coding', 'squad'});
    expect(all.whereType<PersonalIdentity>().single.bundle.skillIds, ['s']);
    expect(all.whereType<TeamIdentity>().single.display, 'Squad');
  });

  test('delete removes the identity dir', () async {
    await repo.save(const PersonalIdentity(id: 'coding', display: 'Coding'));
    await repo.delete('coding');
    expect(await repo.loadAll(), isEmpty);
  });
}
