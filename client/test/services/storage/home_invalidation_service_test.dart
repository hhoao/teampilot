import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/ssh_profile_cubit.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/services/storage/home_invalidation_service.dart';
import 'package:teampilot/services/storage/home_storage.dart';
import 'package:teampilot/services/storage/runtime_context.dart';
import 'package:teampilot/services/storage/app_paths.dart';

import '../../support/in_memory_filesystem.dart';

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

RuntimeContext _context(String root) => RuntimeContext(
  target: RuntimeTarget.local(),
  filesystem: InMemoryFilesystem(),
  home: '$root/home',
  cwd: '$root/home',
  appDataRoot: root,
  paths: AppPaths(root),
);

/// Re-emits each pending microtask hop until the service drain settles.
Future<void> _flush() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _ReloadRecorder {
  final levels = <ReloadLevel>[];

  Future<void> call(ReloadLevel level) async {
    levels.add(level);
  }
}

/// Reload fake that mimics the SSH-home reload chain: the reload reinstalls
/// the storage context, and the reinstall's swap emits a non-identical
/// StoragePlaneChange back into the service's own subscription (the C1 echo).
class _EchoingReloadRecorder {
  final levels = <ReloadLevel>[];
  final StreamController<StoragePlaneChange> storageChanges;

  _EchoingReloadRecorder(this.storageChanges);

  Future<void> call(ReloadLevel level) async {
    levels.add(level);
    // reinstallStorageContext() → homeStorage.swap(fresh wrapper)
    storageChanges.add(
      StoragePlaneChange(
        oldContext: _context('/tp/stale'),
        newContext: _context('/tp/fresh'),
        generation: levels.length,
      ),
    );
  }
}

void main() {
  late StreamController<SshProfileState> profileStates;
  late StreamController<StoragePlaneChange> storageChanges;
  late _ReloadRecorder reload;
  final switchedHomeIds = <String>[];

  HomeInvalidationService startService({
    List<SshProfile> initialProfiles = const [],
  }) {
    final service = HomeInvalidationService(
      profileStates: profileStates.stream,
      storageChanges: storageChanges.stream,
      homeTargetId: () => 'ssh:p1',
      reload: reload.call,
      switchHome: (id) async => switchedHomeIds.add(id),
      initialProfiles: initialProfiles,
    );
    service.start();
    return service;
  }

  setUp(() {
    profileStates = StreamController<SshProfileState>.broadcast();
    storageChanges = StreamController<StoragePlaneChange>.broadcast();
    reload = _ReloadRecorder();
    switchedHomeIds.clear();
  });

  tearDown(() async {
    await profileStates.close();
    await storageChanges.close();
  });

  test('unrelated profile churn does not reload', () async {
    startService(initialProfiles: const [home]);
    profileStates.add(const SshProfileState(profiles: [home, other]));
    profileStates.add(
      SshProfileState(
        profiles: [
          home,
          other.copyWith(name: 'Renamed'),
        ],
      ),
    );
    await _flush();

    expect(reload.levels, isEmpty);
    expect(switchedHomeIds, isEmpty);
  });

  test('home connection change reloads at full level', () async {
    startService(initialProfiles: const [home]);
    profileStates.add(
      SshProfileState(profiles: [home.copyWith(host: 'new.example.com')]),
    );
    await _flush();

    expect(reload.levels, [ReloadLevel.full]);
    expect(switchedHomeIds, isEmpty);
  });

  test('home profile missing switches home instead of reloading', () async {
    startService(initialProfiles: const [home, other]);
    profileStates.add(const SshProfileState(profiles: [other]));
    await _flush();

    expect(switchedHomeIds, [RuntimeTarget.localId]);
    expect(reload.levels, isEmpty);
  });

  test('home storage plane swap reloads at full level', () async {
    startService(initialProfiles: const [home]);
    storageChanges.add(
      StoragePlaneChange(
        oldContext: _context('/tp/a'),
        newContext: _context('/tp/b'),
        generation: 1,
      ),
    );
    await _flush();

    expect(reload.levels, [ReloadLevel.full]);
  });

  test('swap echo from the reload itself does not re-trigger (C1)', () async {
    // SSH home mode: the reload's own reinstallStorageContext swaps in a
    // fresh (non-identical) context, whose change echoes back through
    // storageChanges while the reload is still in flight — that echo must
    // not queue another reload (unbounded reload → swap → reload cycle).
    final echoReload = _EchoingReloadRecorder(storageChanges);
    final service = HomeInvalidationService(
      profileStates: profileStates.stream,
      storageChanges: storageChanges.stream,
      homeTargetId: () => 'ssh:p1',
      reload: echoReload.call,
      switchHome: (id) async => switchedHomeIds.add(id),
      initialProfiles: const [home],
    );
    service.start();
    profileStates.add(
      SshProfileState(profiles: [home.copyWith(host: 'new.example.com')]),
    );
    await _flush();

    expect(echoReload.levels, [ReloadLevel.full]);
    expect(switchedHomeIds, isEmpty);

    // A swap arriving after the reload settled is an external home switch
    // — it still triggers a fresh reload.
    storageChanges.add(
      StoragePlaneChange(
        oldContext: _context('/tp/b'),
        newContext: _context('/tp/c'),
        generation: 99,
      ),
    );
    await _flush();

    expect(echoReload.levels, [ReloadLevel.full, ReloadLevel.full]);
  });

  test(
    'external switch during an in-flight reload queues exactly one follow-up (I-2)',
    () async {
      // Real HomeStorage so swap generations behave exactly like production:
      // monotonic, +1 per swap, each reload's echo one past the barrier.
      final storage = HomeStorage(_context('/tp/a'));
      final levels = <ReloadLevel>[];
      var emittedExternalSwitch = false;
      Future<void> reload(ReloadLevel level) async {
        levels.add(level);
        // reinstallStorageContext(): fresh wrapper for the same plane — the
        // swap's change echoes back while this reload is still in flight.
        await storage.swap(_context('/tp/a-fresh'));
        // On the first reload only, an external home switch races the
        // in-flight reload (a newer generation than the reload's own echo).
        if (!emittedExternalSwitch) {
          emittedExternalSwitch = true;
          await Future<void>.delayed(Duration.zero);
          await storage.swap(_context('/tp/external'));
        }
      }

      final service = HomeInvalidationService(
        profileStates: profileStates.stream,
        storageChanges: storage.changes,
        homeTargetId: () => 'ssh:p1',
        reload: reload,
        switchHome: (id) async => switchedHomeIds.add(id),
        initialProfiles: const [home],
        initialGeneration: storage.generation,
      );
      service.start();
      profileStates.add(
        SshProfileState(profiles: [home.copyWith(host: 'new.example.com')]),
      );
      await _flush();

      // Initial reload + exactly one follow-up for the racing external
      // switch — the follow-up's own echo must not add a third.
      expect(levels, [ReloadLevel.full, ReloadLevel.full]);
      expect(switchedHomeIds, isEmpty);
    },
  );

  test('same-context profile re-emit does not reload', () async {
    startService(initialProfiles: const [home]);
    profileStates.add(const SshProfileState(profiles: [home]));
    profileStates.add(const SshProfileState(profiles: [home]));
    await _flush();

    expect(reload.levels, isEmpty);
    expect(switchedHomeIds, isEmpty);
  });

  test('burst of diffs coalesces into one reload call', () async {
    startService(initialProfiles: const [home]);

    // Two diffs emitted back-to-back within one event-loop turn: the drain
    // is deferred past the turn, so the burst collapses into a single call.
    profileStates.add(
      SshProfileState(profiles: [home.copyWith(host: 'a.example.com')]),
    );
    profileStates.add(
      SshProfileState(profiles: [home.copyWith(host: 'b.example.com')]),
    );
    await _flush();

    expect(reload.levels, [ReloadLevel.full]);
  });

  test(
    'diff queued behind an in-flight reload is drained, not dropped',
    () async {
      startService(initialProfiles: const [home]);
      profileStates.add(
        SshProfileState(profiles: [home.copyWith(host: 'a.example.com')]),
      );
      await _flush();
      expect(reload.levels, [ReloadLevel.full]);

      // A second diff while no drain is running triggers a new reload — the
      // service (unlike the old widget binder) has no mounted state to drop it.
      profileStates.add(
        SshProfileState(profiles: [home.copyWith(host: 'b.example.com')]),
      );
      await _flush();

      expect(reload.levels, [ReloadLevel.full, ReloadLevel.full]);
    },
  );

  test('stop() unsubscribes — later events do not reload', () async {
    final service = startService(initialProfiles: const [home]);
    service.stop();
    profileStates.add(
      SshProfileState(profiles: [home.copyWith(host: 'new.example.com')]),
    );
    await _flush();

    expect(reload.levels, isEmpty);
  });
}
