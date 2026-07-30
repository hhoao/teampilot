import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/services/storage/home_storage_invalidator.dart';

void main() {
  const home = SshProfile(
    id: 'p1',
    name: 'Home',
    host: 'home.example.com',
    username: 'alice',
  );
  const other = SshProfile(
    id: 'p2',
    name: 'Other',
    host: 'other.example.com',
    username: 'bob',
  );

  test('unrelated catalog change does nothing', () async {
    final actions = <String>[];
    final invalidator = HomeStorageInvalidator(
      homeTargetId: () => 'ssh:p1',
      reinstallAndReload: () async => actions.add('reinstall'),
      switchHome: (id) async => actions.add('switch:$id'),
    );

    await invalidator.applyProfilesChanged(
      previous: const [home],
      next: [home, other],
    );

    expect(actions, isEmpty);
  });

  test('home connection change reinstalls and reloads', () async {
    final actions = <String>[];
    final invalidator = HomeStorageInvalidator(
      homeTargetId: () => 'ssh:p1',
      reinstallAndReload: () async => actions.add('reinstall'),
      switchHome: (id) async => actions.add('switch:$id'),
    );

    await invalidator.applyProfilesChanged(
      previous: const [home],
      next: [home.copyWith(host: 'new.example.com')],
    );

    expect(actions, ['reinstall']);
  });

  test('missing home profile falls back to local', () async {
    final actions = <String>[];
    final invalidator = HomeStorageInvalidator(
      homeTargetId: () => 'ssh:p1',
      reinstallAndReload: () async => actions.add('reinstall'),
      switchHome: (id) async => actions.add('switch:$id'),
    );

    await invalidator.applyProfilesChanged(
      previous: [home, other],
      next: const [other],
    );

    expect(actions, ['switch:${RuntimeTarget.localId}']);
  });
}
