import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/models/ssh_reachability.dart';
import 'package:teampilot/services/io/sftp_filesystem.dart';
import 'package:teampilot/services/ssh/ssh_client_factory.dart';
import 'package:teampilot/services/storage/app_paths.dart';
import 'package:teampilot/services/storage/remote_ssh_storage_paths.dart';
import 'package:teampilot/services/storage/runtime_context.dart';
import 'package:teampilot/services/storage/runtime_context_registry.dart';
import 'package:teampilot/services/storage/runtime_context_resolver.dart';

import '../../support/in_memory_filesystem.dart';

class _MockSshClientFactory extends Mock implements SshClientFactory {}

class _FailingPathResolver extends RemoteSshStoragePathResolver {
  _FailingPathResolver({required super.clientFactory});

  @override
  Future<RemoteSshStoragePaths> resolve(SshProfile profile) =>
      Future.error(StateError('resolve failed'));
}

/// Resolver that returns a distinct in-memory context per target id (no IO),
/// counts resolves, and can be told to fail specific targets (offline).
class _FakeResolver extends RuntimeContextResolver {
  _FakeResolver() : super(nativeAppDataPath: '/native');

  final resolveCount = <String, int>{};
  final offline = <String>{};
  final resolvedProfiles = <String, SshProfile?>{};

  @override
  Future<RuntimeContext> resolve(
    RuntimeTarget target, {
    SshProfile? sshProfile,
    String? cachedHome,
    String? cachedAppDataRoot,
  }) async {
    resolveCount[target.id] = (resolveCount[target.id] ?? 0) + 1;
    resolvedProfiles[target.id] = sshProfile;
    if (offline.contains(target.id)) {
      throw StateError('offline: ${target.id}');
    }
    final root = '/tp-${target.id}';
    return RuntimeContext(
      target: target,
      filesystem: InMemoryFilesystem(),
      home: root,
      cwd: root,
      appDataRoot: root,
      paths: AppPaths(root),
    );
  }
}

/// Live resolve never completes; [resolveCached] answers immediately.
class _HangingResolver extends RuntimeContextResolver {
  _HangingResolver() : super(nativeAppDataPath: '/native');

  final live = Completer<RuntimeContext>();

  @override
  Future<RuntimeContext> resolve(
    RuntimeTarget target, {
    SshProfile? sshProfile,
    String? cachedHome,
    String? cachedAppDataRoot,
  }) => live.future;

  @override
  Future<RuntimeContext> resolveCached(
    RuntimeTarget target, {
    SshProfile? sshProfile,
  }) async => RuntimeContext(
    target: target,
    filesystem: InMemoryFilesystem(),
    home: '/cached-home',
    cwd: '/cached-home',
    appDataRoot: '/cached-app',
    paths: const AppPaths('/cached-app'),
    pathsFromCache: true,
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(
      const SshProfile(
        id: 'p1',
        name: 'Remote',
        host: 'example.com',
        username: 'u',
      ),
    );
  });

  test(
    'ensureHome ssh with persisted lastHome soft-fails when SFTP is down',
    () async {
      final factory = _MockSshClientFactory();
      when(
        () => factory.ensureStorageConnected(any()),
      ).thenThrow(StateError('host down'));
      final profile = SshProfile(
        id: 'p1',
        name: 'Remote',
        host: 'example.com',
        username: 'u',
        lastHome: '/home/u',
        lastAppDataRoot: '/home/u/.local/share/com.hhoa.teampilot',
      );
      final resolver = RuntimeContextResolver(
        sshClientFactory: factory,
        nativeAppDataPath: '/native',
        remotePathResolver: _FailingPathResolver(clientFactory: factory),
      );
      final reg = RuntimeContextRegistry(
        resolver: resolver,
        homeTarget: RuntimeTarget.ssh('p1', label: 'Remote'),
        sshProfileById: (id) => id == 'p1' ? profile : null,
      );
      await reg.ensureHome();
      final home = reg.home();
      expect(home.target.kind, RuntimeKind.ssh);
      expect(home.pathsFromCache, isTrue);
      expect(home.home, '/home/u');
      expect(home.appDataRoot, '/home/u/.local/share/com.hhoa.teampilot');
      expect(home.filesystem, isA<SftpFilesystem>());
    },
  );

  test('home() returns the bootstrapped home context', () async {
    final reg = RuntimeContextRegistry(
      resolver: _FakeResolver(),
      homeTarget: RuntimeTarget.local(),
    );
    await reg.ensureHome();
    expect(reg.home().appDataRoot, '/tp-local');
  });

  test('home() throws before ensureHome', () {
    final reg = RuntimeContextRegistry(
      resolver: _FakeResolver(),
      homeTarget: RuntimeTarget.local(),
    );
    expect(reg.home, throwsStateError);
  });

  test('forTarget caches by id (same instance, single resolve)', () async {
    final resolver = _FakeResolver();
    final reg = RuntimeContextRegistry(
      resolver: resolver,
      homeTarget: RuntimeTarget.local(),
    );
    final a = await reg.forTarget(RuntimeTarget.ssh('p1', label: 'box'));
    final b = await reg.forTarget(RuntimeTarget.ssh('p1', label: 'box'));
    expect(identical(a, b), isTrue);
    expect(resolver.resolveCount['ssh:p1'], 1);
  });

  test('ensureHomeCached answers without waiting for a live resolve', () async {
    final resolver = _HangingResolver();
    final reg = RuntimeContextRegistry(
      resolver: resolver,
      homeTarget: RuntimeTarget.ssh('p1', label: 'Remote'),
    );
    final live = reg.ensureHome(); // in flight, never completes on its own
    final cached = await reg.ensureHomeCached().timeout(
      const Duration(milliseconds: 200),
    );
    expect(cached.pathsFromCache, isTrue);
    expect(cached.appDataRoot, '/cached-app');
    expect(reg.home(), same(cached));

    // A live resolve finishing later still wins over the cached placeholder.
    resolver.live.complete(
      RuntimeContext(
        target: RuntimeTarget.ssh('p1', label: 'Remote'),
        filesystem: InMemoryFilesystem(),
        home: '/live-home',
        cwd: '/live-home',
        appDataRoot: '/live-app',
        paths: const AppPaths('/live-app'),
      ),
    );
    await live;
    expect(reg.home().appDataRoot, '/live-app');
    expect(reg.home().pathsFromCache, isFalse);
  });

  test('two targets resolve to independent contexts', () async {
    final reg = RuntimeContextRegistry(
      resolver: _FakeResolver(),
      homeTarget: RuntimeTarget.local(),
    );
    await reg.ensureHome();
    final ssh = await reg.forTarget(RuntimeTarget.ssh('p1', label: 'box'));
    expect(reg.home().appDataRoot, '/tp-local');
    expect(ssh.appDataRoot, '/tp-ssh:p1');
    expect(identical(reg.home().filesystem, ssh.filesystem), isFalse);
  });

  test(
    'forTarget(ssh) failure does not break home() reads (offline)',
    () async {
      final resolver = _FakeResolver()..offline.add('ssh:gone');
      final reg = RuntimeContextRegistry(
        resolver: resolver,
        homeTarget: RuntimeTarget.local(),
      );
      await reg.ensureHome();
      await expectLater(
        reg.forTarget(RuntimeTarget.ssh('gone', label: 'x')),
        throwsStateError,
      );
      // Project list / control-plane reads still work.
      expect(reg.home().appDataRoot, '/tp-local');
    },
  );

  test('dispose evicts cached context (re-resolves next time)', () async {
    final resolver = _FakeResolver();
    final reg = RuntimeContextRegistry(
      resolver: resolver,
      homeTarget: RuntimeTarget.local(),
    );
    final t = RuntimeTarget.ssh('p1', label: 'box');
    await reg.forTarget(t);
    await reg.dispose('ssh:p1');
    await reg.forTarget(t);
    expect(resolver.resolveCount['ssh:p1'], 2);
  });

  test('dispose(notifyEvict: false) drops cache without onEvict', () async {
    final evicted = <String>[];
    final resolver = _FakeResolver();
    final reg = RuntimeContextRegistry(
      resolver: resolver,
      homeTarget: RuntimeTarget.local(),
      onEvict: (id) async => evicted.add(id),
    );
    final t = RuntimeTarget.ssh('p1', label: 'box');
    await reg.forTarget(t);

    await reg.dispose('ssh:p1', notifyEvict: false);

    expect(evicted, isEmpty);
    await reg.forTarget(t);
    expect(resolver.resolveCount['ssh:p1'], 2);
  });

  test(
    'failed home reinstall keeps the previous home context available',
    () async {
      final evicted = <String>[];
      final resolver = _FakeResolver();
      final reg = RuntimeContextRegistry(
        resolver: resolver,
        homeTarget: RuntimeTarget.ssh('p1', label: 'Remote'),
        onEvict: (id) async => evicted.add(id),
      );
      await reg.ensureHome();
      resolver.offline.add('ssh:p1');

      await expectLater(
        reg.rebindHome(RuntimeTarget.ssh('p1', label: 'Remote')),
        throwsStateError,
      );

      expect(reg.home().appDataRoot, '/tp-ssh:p1');
      await reg.dispose('ssh:p1');
      expect(evicted, ['ssh:p1']);
    },
  );

  test('dispose notifies onEvict for remote contexts by default', () async {
    final evicted = <String>[];
    final reg = RuntimeContextRegistry(
      resolver: _FakeResolver(),
      homeTarget: RuntimeTarget.local(),
      onEvict: (id) async => evicted.add(id),
    );
    await reg.forTarget(RuntimeTarget.ssh('p1', label: 'box'));

    await reg.dispose('ssh:p1');

    expect(evicted, ['ssh:p1']);
  });

  test('rebindHome swaps the home context', () async {
    final reg = RuntimeContextRegistry(
      resolver: _FakeResolver(),
      homeTarget: RuntimeTarget.local(),
    );
    await reg.ensureHome();
    expect(reg.home().appDataRoot, '/tp-local');
    await reg.rebindHome(RuntimeTarget.wsl('Ubuntu'));
    expect(reg.home().appDataRoot, '/tp-wsl:Ubuntu');
  });

  test('every work target resolves from the device catalog', () async {
    const aHome = SshProfile(
      id: 'home',
      name: 'A home',
      host: 'a.home',
      username: 'u',
    );
    const aWork = SshProfile(
      id: 'work',
      name: 'A work',
      host: 'a.work',
      username: 'u',
    );
    final resolver = _FakeResolver();
    final reg = RuntimeContextRegistry(
      resolver: resolver,
      homeTarget: RuntimeTarget.ssh('home', label: 'Home'),
      sshProfileById: (id) => {'home': aHome, 'work': aWork}[id],
    );

    await reg.ensureHome();
    await reg.forTarget(RuntimeTarget.ssh('work', label: 'Work'));

    expect(resolver.resolvedProfiles['ssh:home']?.host, 'a.home');
    expect(resolver.resolvedProfiles['ssh:work']?.host, 'a.work');
  });

  group('profile-source contract', () {
    test('a local home never consults the SSH catalog', () async {
      var calls = 0;
      final resolver = _FakeResolver();
      final reg = RuntimeContextRegistry(
        resolver: resolver,
        homeTarget: RuntimeTarget.local(),
        sshProfileById: (id) {
          calls++;
          return null;
        },
      );

      await reg.ensureHome();

      expect(calls, 0);
      expect(resolver.resolvedProfiles.containsKey('local'), isTrue);
      expect(resolver.resolvedProfiles['local'], isNull);
    });

    test('the home id used as a work target reuses the home context', () async {
      const aHome = SshProfile(
        id: 'home',
        name: 'A home',
        host: 'a.home',
        username: 'u',
      );
      final resolver = _FakeResolver();
      final homeTarget = RuntimeTarget.ssh('home', label: 'Home');
      final reg = RuntimeContextRegistry(
        resolver: resolver,
        homeTarget: homeTarget,
        sshProfileById: (id) => id == 'home' ? aHome : null,
      );

      await reg.ensureHome();
      final viaWork = await reg.forTarget(homeTarget);

      expect(identical(viaWork, reg.home()), isTrue);
      expect(resolver.resolveCount['ssh:home'], 1);
    });

    test('a plan change rebuilds the cached work context', () async {
      const first = SshProfile(
        id: 'work',
        name: 'Work',
        host: 'first.work',
        username: 'u',
      );
      const rewritten = SshProfile(
        id: 'work',
        name: 'Work',
        host: 'second.work',
        username: 'u',
      );
      var current = first;
      final resolver = _FakeResolver();
      final reg = RuntimeContextRegistry(
        resolver: resolver,
        homeTarget: RuntimeTarget.local(),
        sshProfileById: (id) => id == 'work' ? current : null,
      );
      final target = RuntimeTarget.ssh('work', label: 'Work');

      final before = await reg.forTarget(target);
      current = rewritten;
      final after = await reg.forTarget(target);

      expect(identical(before, after), isFalse);
      expect(resolver.resolveCount['ssh:work'], 2);
      expect(resolver.resolvedProfiles['ssh:work']?.host, 'second.work');
    });

    test('last-good preference changes keep the cached context', () async {
      const lan = SshReachabilityEndpoint(
        kind: SshEndpointKind.lan,
        host: 'h',
        port: 22,
      );
      const extra = SshReachabilityEndpoint(
        kind: SshEndpointKind.extra,
        host: '203.0.113.9',
        port: 22,
      );
      const lanWin = SshProfile(
        id: 'work',
        name: 'Work',
        host: 'h',
        username: 'u',
        endpoints: [lan, extra],
        lastGoodKind: SshEndpointKind.lan,
      );
      const extraWin = SshProfile(
        id: 'work',
        name: 'Work',
        host: '203.0.113.9',
        username: 'u',
        endpoints: [lan, extra],
        lastGoodKind: SshEndpointKind.extra,
      );
      var current = lanWin;
      final resolver = _FakeResolver();
      final reg = RuntimeContextRegistry(
        resolver: resolver,
        homeTarget: RuntimeTarget.local(),
        sshProfileById: (id) => id == 'work' ? current : null,
      );
      final target = RuntimeTarget.ssh('work', label: 'Work');

      final before = await reg.forTarget(target);
      current = extraWin;
      final after = await reg.forTarget(target);

      expect(identical(before, after), isTrue);
      expect(resolver.resolveCount['ssh:work'], 1);
    });

    test('a name-only change keeps the cached context', () async {
      const original = SshProfile(
        id: 'work',
        name: 'Work',
        host: 'h',
        username: 'u',
      );
      const renamed = SshProfile(
        id: 'work',
        name: 'Renamed',
        host: 'h',
        username: 'u',
      );
      var current = original;
      final resolver = _FakeResolver();
      final reg = RuntimeContextRegistry(
        resolver: resolver,
        homeTarget: RuntimeTarget.local(),
        sshProfileById: (id) => id == 'work' ? current : null,
      );

      await reg.forTarget(RuntimeTarget.ssh('work', label: 'Work'));
      current = renamed;
      await reg.forTarget(RuntimeTarget.ssh('work', label: 'Work'));

      expect(resolver.resolveCount['ssh:work'], 1);
    });

    test('an unknown id resolves with no profile (no guess)', () async {
      final resolver = _FakeResolver();
      final reg = RuntimeContextRegistry(
        resolver: resolver,
        homeTarget: RuntimeTarget.local(),
        sshProfileById: (id) => null,
      );

      await reg.forTarget(RuntimeTarget.ssh('ghost', label: 'Ghost'));

      expect(resolver.resolvedProfiles.containsKey('ssh:ghost'), isTrue);
      expect(resolver.resolvedProfiles['ssh:ghost'], isNull);
    });

    test('work resolution does not depend on the home target kind', () async {
      const workProfile = SshProfile(
        id: 'work',
        name: 'Work',
        host: 'w',
        username: 'u',
      );

      Future<String?> resolvedHost(RuntimeTarget homeTarget) async {
        final resolver = _FakeResolver();
        final reg = RuntimeContextRegistry(
          resolver: resolver,
          homeTarget: homeTarget,
          sshProfileById: (id) => id == 'work' ? workProfile : null,
        );
        await reg.ensureHome();
        await reg.forTarget(RuntimeTarget.ssh('work', label: 'Work'));
        return resolver.resolvedProfiles['ssh:work']?.host;
      }

      // A desktop with a local home and an SSH workspace takes the same path
      // as a device homed to SSH: home kind is a transport detail.
      expect(await resolvedHost(RuntimeTarget.local()), 'w');
      expect(
        await resolvedHost(RuntimeTarget.ssh('home', label: 'Home')),
        'w',
      );
    });

    test(
      'an ssh target without a connection is never degraded to the local FS',
      () async {
        await expectLater(
          RuntimeContextResolver(
            nativeAppDataPath: '/native',
          ).resolve(RuntimeTarget.ssh('ghost', label: 'Ghost')),
          throwsStateError,
        );
      },
    );
  });
}
