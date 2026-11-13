import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/ssh_workload_profile_cubit.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/storage/home_storage.dart';

import '../support/in_memory_filesystem.dart';

void main() {
  group('SshWorkloadProfileCubit', () {
    test('load reads the home-plane server catalog (B source)', () async {
      final storage = await _plane(['plane-a']);
      final cubit = SshWorkloadProfileCubit(storage: storage);
      addTearDown(cubit.close);

      await cubit.load();

      expect(cubit.state.profiles.map((p) => p.id), ['plane-a']);
    });

    test(
      'a home-plane swap rebuilds the repository and reloads new plane entries',
      () async {
        final first = await _plane(['plane-a']);
        final second = await _plane(['plane-b', 'plane-c']);
        final cubit = SshWorkloadProfileCubit(storage: first);
        addTearDown(cubit.close);

        await cubit.load();
        expect(cubit.state.profiles.map((p) => p.id), ['plane-a']);

        // A swap mutates the injected HomeStorage in place and publishes a
        // StoragePlaneChange; the cubit must re-read the new plane's catalog.
        await first.swap(second.context);
        await pumpEventQueue();
        await pumpEventQueue();

        expect(
          cubit.state.profiles.map((p) => p.id),
          ['plane-b', 'plane-c'],
        );
      },
    );

    test(
      'a remote read failure emits an empty list instead of throwing',
      () async {
        final storage = fakeHomeStorage(filesystem: _ThrowingStatFilesystem());
        final cubit = SshWorkloadProfileCubit(storage: storage);
        addTearDown(cubit.close);

        await cubit.load();

        expect(cubit.state.profiles, isEmpty);
      },
    );
  });
}

Future<HomeStorage> _plane(List<String> ids) async {
  final storage = fakeHomeStorage();
  final fs = storage.fs;
  final file = fs.pathContext.join(
    storage.paths.sshProfilesDir,
    'profiles.json',
  );
  await fs.atomicWrite(
    file,
    jsonEncode([for (final id in ids) _row(id)]),
  );
  return storage;
}

Map<String, Object?> _row(String id) => {
  'schemaVersion': 1,
  'id': id,
  'name': id,
  'host': 'h',
  'port': 22,
  'username': 'u',
  'authType': 'password',
  'updatedAt': 1,
};

/// Simulates a dropped/remote home plane: stat is the first read in
/// `SshServerProfileRepository`, so a failure there propagates out of
/// `PlaneSshProfileRepository.loadAll()`.
class _ThrowingStatFilesystem extends InMemoryFilesystem {
  @override
  Future<FsStat> stat(String path) async {
    throw StateError('ssh transport closed');
  }
}
