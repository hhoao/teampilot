import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/ssh_workload_profile_cubit.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/repositories/connection_store.dart';
import 'package:teampilot/services/storage/home_storage.dart';

import '../support/in_memory_filesystem.dart';

SshWorkloadProfileCubit _cubit(HomeStorage storage) => SshWorkloadProfileCubit(
  storage: storage,
  connections: ConnectionStore(rootDir: '/device', fs: storage.fs),
);

void main() {
  group('SshWorkloadProfileCubit', () {
    test('load reads the home-plane server catalog (B source)', () async {
      final storage = await _plane(['plane-a']);
      final cubit = _cubit(storage);
      addTearDown(cubit.close);

      await cubit.load();

      expect(cubit.state.profiles.map((p) => p.id), ['plane-a']);
    });

    test(
      'a home-plane swap reloads new plane entries on the same instance',
      () async {
        final first = await _plane(['plane-a']);
        final second = await _plane(['plane-b', 'plane-c']);
        final cubit = _cubit(first);
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
      'a swap during an in-flight load is re-read, not coalesced away',
      () async {
        final gated = _GatedFilesystem();
        final first = await _plane(['plane-a'], filesystem: gated);
        final second = await _plane(['plane-b', 'plane-c']);
        final cubit = _cubit(first);
        addTearDown(cubit.close);

        // Hold the first read at the filesystem boundary (a slow SSH read).
        // HomeStorage keeps the old transport alive during a swap, so this
        // in-flight load will finish against plane A and emit its old rows.
        final inFlight = cubit.load();
        await gated.entered.future;

        // Publish the swap while that read is still in flight, then let the
        // changes listener observe it before the old read is released.
        await first.swap(second.context);
        await pumpEventQueue();

        // The old read now completes; a queued re-read must observe plane B,
        // otherwise the swap is lost until the next change event.
        gated.release.complete();
        await inFlight;

        expect(
          cubit.state.profiles.map((p) => p.id),
          ['plane-b', 'plane-c'],
        );
      },
    );

    test(
      'a remote read failure emits an empty list and logs a diagnostic',
      () async {
        final storage = fakeHomeStorage(
          filesystem: _ToggleableFailureFilesystem()..fail = true,
        );
        final cubit = _cubit(storage);
        addTearDown(cubit.close);

        // Capture AppLogger console output so the warning is asserted rather
        // than printed into the test log (pristine run output).
        final printed = await _capturePrint(() => cubit.load());

        expect(cubit.state.profiles, isEmpty);
        expect(printed.join('\n'), contains('[ssh-workload]'));
      },
    );

    test(
      'a read failure after a populated load clears the stale profiles',
      () async {
        final fs = _ToggleableFailureFilesystem();
        final storage = await _plane(['plane-a'], filesystem: fs);
        final cubit = _cubit(storage);
        addTearDown(cubit.close);

        await cubit.load();
        expect(cubit.state.profiles.map((p) => p.id), ['plane-a']);

        // The plane drops: the next read fails and must clear the previously
        // loaded (now stale) catalog, not just start from an already-empty one.
        fs.fail = true;
        final printed = await _capturePrint(() => cubit.load());

        expect(cubit.state.profiles, isEmpty);
        expect(printed.join('\n'), contains('[ssh-workload]'));
      },
    );
  });
}

/// Runs [body] in a zone that collects [print] output (AppLogger's
/// ConsoleOutput prints), so diagnostics stay out of the test log.
Future<List<String>> _capturePrint(Future<void> Function() body) async {
  final lines = <String>[];
  await runZoned(
    body,
    zoneSpecification: ZoneSpecification(
      print: (Zone self, ZoneDelegate parent, Zone zone, String line) {
        lines.add(line);
      },
    ),
  );
  return lines;
}

Future<HomeStorage> _plane(
  List<String> ids, {
  InMemoryFilesystem? filesystem,
}) async {
  final storage = fakeHomeStorage(filesystem: filesystem);
  final fs = storage.fs;
  final file = fs.pathContext.join(
    storage.paths.sshProfilesDir,
    'profiles.json',
  );
  await fs.atomicWrite(file, jsonEncode([for (final id in ids) _row(id)]));
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

/// Blocks [readString] until [release] completes and signals [entered] when a
/// read reaches it, so a test can publish a swap mid-load.
class _GatedFilesystem extends InMemoryFilesystem {
  final entered = Completer<void>();
  final release = Completer<void>();

  @override
  Future<String?> readString(String path) async {
    if (!entered.isCompleted) entered.complete();
    await release.future;
    return super.readString(path);
  }
}

/// Simulates a dropped/remote home plane when [fail] is set: stat is the first
/// read in SshServerProfileRepository, so a failure there propagates out of
/// PlaneSshProfileRepository.loadAll().
class _ToggleableFailureFilesystem extends InMemoryFilesystem {
  bool fail = false;

  @override
  Future<FsStat> stat(String path) async {
    if (fail) throw StateError('ssh transport closed');
    return super.stat(path);
  }
}
