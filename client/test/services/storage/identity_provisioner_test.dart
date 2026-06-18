import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/identity_kind.dart';
import 'package:teampilot/repositories/identity_repository.dart';
import 'package:teampilot/services/storage/identity_provisioner.dart';

import '../../support/post_frame_test_harness.dart';

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  test('provisions exactly one default personal identity on empty store', () async {
    final tmp = await Directory.systemTemp.createTemp('identity_prov_');
    final repo = IdentityRepository(rootDir: tmp.path);
    final provisioner = IdentityProvisioner(repository: repo);

    final first = await provisioner.ensureDefaultPersonal();
    final again = await provisioner.ensureDefaultPersonal();

    expect(first.id, IdentityProvisioner.defaultPersonalId);
    expect(first.kind, IdentityKind.personal);
    expect(again.id, first.id);
    final all = await repo.loadAll();
    expect(all.where((e) => e.kind == IdentityKind.personal).length, 1);
    await tmp.delete(recursive: true);
  });
}
