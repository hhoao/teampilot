import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/launch_profile_repository.dart';

import '../support/post_frame_test_harness.dart';

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  late Directory tmp;
  late LaunchProfileRepository repo;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('identity_repo_');
    repo = testLaunchProfileRepository(tmp);
  });
  tearDown(() async => deleteTempDirBestEffort(tmp));

  test('saves and loads team profiles', () async {
    await repo.save(
      const TeamProfile(
        id: 'squad',
        name: 'Squad',
        skillIds: ['s'],
      ),
    );

    final all = await repo.loadAll();
    expect(all.map((e) => e.id).toSet(), {'squad'});
    expect(all.whereType<TeamProfile>().single.skillIds, ['s']);
  });

  test('delete removes the identity dir', () async {
    await repo.save(const TeamProfile(id: 'squad', name: 'Squad'));
    await repo.delete('squad');
    expect(await repo.loadAll(), isEmpty);
  });

  test('loadAll maintains launch-profiles-index.json snapshot', () async {
    await repo.save(const TeamProfile(id: 'squad', name: 'Squad'));
    await repo.save(const TeamProfile(id: 'alpha', name: 'Alpha'));

    final resolvedIndex = p.join(tmp.path, 'launch-profiles-index.json');
    expect(File(resolvedIndex).existsSync(), isTrue);

    final fromSnapshot = await repo.loadAll();
    expect(fromSnapshot.map((e) => e.id).toSet(), {'squad', 'alpha'});

    await repo.delete('squad');
    final afterDelete = await repo.loadAll();
    expect(afterDelete.map((e) => e.id).toList(), ['alpha']);
    final decoded = jsonDecode(File(resolvedIndex).readAsStringSync());
    expect((decoded as Map)['profiles'], hasLength(1));
  });
}
