import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/launch_profile_cubit.dart';
import 'package:teampilot/models/config_bundle.dart';
import 'package:teampilot/models/personal_profile.dart';
import 'package:teampilot/repositories/launch_profile_repository.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/session/session_lifecycle_service.dart';

import '../support/post_frame_test_harness.dart';

LaunchProfileRepository _repo(Directory dir) => LaunchProfileRepository(rootDir: dir.path);

LaunchProfileCubit _cubit(Directory dir, LaunchProfileRepository repo) => LaunchProfileCubit(
      repository: repo,
      sessionRepository: SessionRepository(
        lifecycleService: SessionLifecycleService(appDataBasePath: dir.path),
      ),
      executableResolver: () => 'claude',
    );

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  late Directory tmp;
  late LaunchProfileRepository repo;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('identity_cubit_personal_');
    repo = _repo(tmp);
  });
  tearDown(() => tmp.delete(recursive: true));

  test('save personal appears in personals', () async {
    final cubit = _cubit(tmp, repo);
    await cubit.load();
    await cubit.savePersonal(
      const PersonalProfile(id: 'coding', display: 'Coding'),
    );
    expect(cubit.state.personals.map((p) => p.id), contains('coding'));
    await cubit.close();
  });

  test('deleting the only personal is a no-op', () async {
    final cubit = _cubit(tmp, repo);
    await cubit.savePersonal(
      const PersonalProfile(id: 'only', display: 'Only'),
    );
    await cubit.deletePersonal('only');
    expect(cubit.state.personals, isNotEmpty);
    await cubit.close();
  });

  test('addPersonal creates a named personal identity', () async {
    final cubit = _cubit(tmp, repo);
    await cubit.load();
    final ok = await cubit.addPersonal('Writing');
    expect(ok, isTrue);
    expect(cubit.state.personals.map((p) => p.display), contains('Writing'));
    await cubit.close();
  });

  test('deleting when more than one removes the identity', () async {
    final cubit = _cubit(tmp, repo);
    await cubit.savePersonal(
      const PersonalProfile(id: 'a', display: 'A'),
    );
    await cubit.savePersonal(
      const PersonalProfile(
        id: 'b',
        display: 'B',
        bundle: ConfigBundle(skillIds: ['s']),
      ),
    );
    expect(cubit.state.personals.length, 2);
    await cubit.deletePersonal('b');
    expect(cubit.state.personals.map((p) => p.id), ['a']);
    await cubit.close();
  });

  test('reorderPersonals persists sortOrder for all personals', () async {
    final cubit = _cubit(tmp, repo);
    await cubit.savePersonal(
      const PersonalProfile(id: 'first', display: 'First', createdAt: 1),
    );
    await cubit.savePersonal(
      const PersonalProfile(id: 'second', display: 'Second', createdAt: 2),
    );
    await cubit.savePersonal(
      const PersonalProfile(id: 'third', display: 'Third', createdAt: 3),
    );

    await cubit.reorderPersonals(0, 3);

    expect(cubit.state.personals.map((p) => p.display).toList(), [
      'Second',
      'Third',
      'First',
    ]);
    expect(cubit.state.personals.map((p) => p.sortOrder).toList(), [1, 2, 3]);

    final reloaded = await repo.loadPersonalProfiles();
    expect(reloaded.map((p) => p.display).toList(), [
      'Second',
      'Third',
      'First',
    ]);
    await cubit.close();
  });
}
