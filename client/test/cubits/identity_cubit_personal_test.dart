import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/identity_cubit.dart';
import 'package:teampilot/models/config_bundle.dart';
import 'package:teampilot/models/personal_identity.dart';
import 'package:teampilot/repositories/identity_repository.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/session/session_lifecycle_service.dart';

import '../support/post_frame_test_harness.dart';

IdentityRepository _repo(Directory dir) => IdentityRepository(rootDir: dir.path);

IdentityCubit _cubit(Directory dir, IdentityRepository repo) => IdentityCubit(
      repository: repo,
      sessionRepository: SessionRepository(
        lifecycleService: SessionLifecycleService(appDataBasePath: dir.path),
      ),
      reloadProjects: () async {},
      executableResolver: () => 'claude',
    );

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  late Directory tmp;
  late IdentityRepository repo;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('identity_cubit_personal_');
    repo = _repo(tmp);
  });
  tearDown(() => tmp.delete(recursive: true));

  test('save personal appears in personals', () async {
    final cubit = _cubit(tmp, repo);
    await cubit.load();
    await cubit.savePersonal(
      const PersonalIdentity(id: 'coding', display: 'Coding'),
    );
    expect(cubit.state.personals.map((p) => p.id), contains('coding'));
    await cubit.close();
  });

  test('deleting the only personal is a no-op', () async {
    final cubit = _cubit(tmp, repo);
    await cubit.savePersonal(
      const PersonalIdentity(id: 'only', display: 'Only'),
    );
    await cubit.deletePersonal('only');
    expect(cubit.state.personals, isNotEmpty);
    await cubit.close();
  });

  test('deleting when more than one removes the identity', () async {
    final cubit = _cubit(tmp, repo);
    await cubit.savePersonal(
      const PersonalIdentity(id: 'a', display: 'A'),
    );
    await cubit.savePersonal(
      const PersonalIdentity(
        id: 'b',
        display: 'B',
        bundle: const ConfigBundle(skillIds: ['s']),
      ),
    );
    expect(cubit.state.personals.length, 2);
    await cubit.deletePersonal('b');
    expect(cubit.state.personals.map((p) => p.id), ['a']);
    await cubit.close();
  });
}
