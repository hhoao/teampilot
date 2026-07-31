import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/services/io/sftp_filesystem.dart';
import 'package:teampilot/services/ssh/ssh_client_factory.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/storage/remote_ssh_storage_paths.dart';
import 'package:teampilot/services/storage/runtime_context.dart';
import 'package:teampilot/services/storage/runtime_context_registry.dart';
import 'package:teampilot/services/storage/runtime_context_resolver.dart';

import '../../support/in_memory_filesystem.dart';

class _MockSshClientFactory extends Mock implements SshClientFactory {}

class _MockSftpClient extends Mock implements SftpClient {}

class _FailingPathResolver extends RemoteSshStoragePathResolver {
  _FailingPathResolver({required SshClientFactory clientFactory})
    : super(clientFactory: clientFactory);

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

  @override
  Future<RuntimeContext> resolve(
    RuntimeTarget target, {
    SshProfile? sshProfile,
    String? cachedHome,
    String? cachedAppDataRoot,
  }) async {
    resolveCount[target.id] = (resolveCount[target.id] ?? 0) + 1;
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

void main() {
  setUpAll(() {
    registerFallbackValue(
      const SshProfile(id: 'p1', name: 'Remote', host: 'example.com', username: 'u'),
    );
  });

  test(
    'ensureHome ssh with persisted lastHome soft-fails when SFTP is down',
    () async {
      final factory = _MockSshClientFactory();
      when(() => factory.sftpFor(any())).thenThrow(StateError('host down'));
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
}
