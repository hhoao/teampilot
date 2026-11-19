import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/services/io/sftp_filesystem.dart';
import 'package:teampilot/services/ssh/ssh_client_factory.dart';
import 'package:teampilot/services/storage/remote_ssh_storage_paths.dart';
import 'package:teampilot/services/storage/runtime_context.dart';
import 'package:teampilot/services/storage/runtime_context_resolver.dart';
import 'package:teampilot/services/termux/termux_config.dart';
import 'package:teampilot/services/termux/termux_transport_profile.dart';

class _MockSshClientFactory extends Mock implements SshClientFactory {}

class _FakePathResolver extends RemoteSshStoragePathResolver {
  _FakePathResolver({required super.clientFactory, required this.onResolve});

  final Future<RemoteSshStoragePaths> Function(SshProfile profile) onResolve;

  @override
  Future<RemoteSshStoragePaths> resolve(SshProfile profile) =>
      onResolve(profile);
}

void main() {
  late Directory tmp;
  late SshProfile termuxProfile;

  setUpAll(() {
    registerFallbackValue(
      const SshProfile(
        id: 'termux',
        name: 'Termux',
        host: '127.0.0.1',
        username: 'u',
      ),
    );
  });

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('rcr_termux_');
    termuxProfile = termuxTransportProfile(
      const TermuxConfig(username: 'u0_a123', port: 8022),
    );
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  test('local target installs native context', () async {
    final resolver = RuntimeContextResolver(
      nativeAppDataPath: tmp.path,
      nativeHome: tmp.path,
      nativeCwd: tmp.path,
    );
    final ctx = await resolver.resolve(RuntimeTarget.local());
    expect(ctx.target.kind, RuntimeKind.local);
    expect(ctx.mode, StorageBackendMode.native);
    expect(ctx.appDataRoot, tmp.path);
  });

  test('termux with working SSH transport resolves sftp context', () async {
    final factory = _MockSshClientFactory();
    when(() => factory.ensureStorageConnected(any())).thenAnswer((_) async {});

    final resolver = RuntimeContextResolver(
      sshClientFactory: factory,
      nativeAppDataPath: tmp.path,
      remotePathResolver: _FakePathResolver(
        clientFactory: factory,
        onResolve: (_) async => const RemoteSshStoragePaths(
          home: '/data/data/com.termux/files/home',
          teampilotAppDir:
              '/data/data/com.termux/files/home/.local/share/com.hhoa.teampilot',
        ),
      ),
    );

    final ctx = await resolver.resolve(
      RuntimeTarget.termux(),
      sshProfile: termuxProfile,
    );

    expect(ctx.target.kind, RuntimeKind.termux);
    expect(ctx.mode, StorageBackendMode.ssh);
    expect(ctx.filesystem, isA<SftpFilesystem>());
    expect(ctx.home, '/data/data/com.termux/files/home');
    expect(
      ctx.appDataRoot,
      '/data/data/com.termux/files/home/.local/share/com.hhoa.teampilot',
    );
    verify(() => factory.ensureStorageConnected(termuxProfile)).called(1);
  });

  test(
    'termux SFTP failure with cached paths falls back without throwing',
    () async {
      final factory = _MockSshClientFactory();
      when(
        () => factory.ensureStorageConnected(any()),
      ).thenThrow(StateError('sshd down'));

      final resolver = RuntimeContextResolver(
        sshClientFactory: factory,
        nativeAppDataPath: tmp.path,
        remotePathResolver: _FakePathResolver(
          clientFactory: factory,
          onResolve: (_) async => const RemoteSshStoragePaths(
            home: '/data/data/com.termux/files/home',
            teampilotAppDir:
                '/data/data/com.termux/files/home/.local/share/com.hhoa.teampilot',
          ),
        ),
      );

      final ctx = await resolver.resolve(
        RuntimeTarget.termux(),
        sshProfile: termuxProfile,
        cachedHome: '/data/data/com.termux/files/home',
        cachedAppDataRoot:
            '/data/data/com.termux/files/home/.local/share/com.hhoa.teampilot',
      );

      expect(ctx.target.kind, RuntimeKind.termux);
      expect(ctx.mode, StorageBackendMode.ssh);
      expect(ctx.pathsFromCache, isTrue);
      expect(ctx.home, '/data/data/com.termux/files/home');
      expect(
        ctx.appDataRoot,
        '/data/data/com.termux/files/home/.local/share/com.hhoa.teampilot',
      );
    },
  );

  test('ssh SFTP failure with profile path cache soft-fails', () async {
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
      nativeAppDataPath: tmp.path,
      remotePathResolver: _FakePathResolver(
        clientFactory: factory,
        onResolve: (_) => Future.error(StateError('resolve failed')),
      ),
    );
    final ctx = await resolver.resolve(
      RuntimeTarget.ssh('p1', label: 'Remote'),
      sshProfile: profile,
      cachedHome: profile.lastHome,
      cachedAppDataRoot: profile.lastAppDataRoot,
    );
    expect(ctx.target.kind, RuntimeKind.ssh);
    expect(ctx.pathsFromCache, isTrue);
    expect(ctx.home, '/home/u');
    expect(ctx.appDataRoot, '/home/u/.local/share/com.hhoa.teampilot');
  });

  test('ssh failure without cache rethrows', () async {
    final factory = _MockSshClientFactory();
    when(
      () => factory.ensureStorageConnected(any()),
    ).thenThrow(StateError('host down'));
    final profile = const SshProfile(
      id: 'p1',
      name: 'Remote',
      host: 'example.com',
      username: 'u',
    );
    final resolver = RuntimeContextResolver(
      sshClientFactory: factory,
      nativeAppDataPath: tmp.path,
      remotePathResolver: _FakePathResolver(
        clientFactory: factory,
        onResolve: (_) => Future.error(StateError('resolve failed')),
      ),
    );
    await expectLater(
      () => resolver.resolve(
        RuntimeTarget.ssh('p1', label: 'Remote'),
        sshProfile: profile,
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('termux failure without cache rethrows', () async {
    final factory = _MockSshClientFactory();
    when(
      () => factory.ensureStorageConnected(any()),
    ).thenThrow(StateError('sshd down'));

    final resolver = RuntimeContextResolver(
      sshClientFactory: factory,
      nativeAppDataPath: tmp.path,
      remotePathResolver: _FakePathResolver(
        clientFactory: factory,
        onResolve: (_) => Future.error(StateError('resolve failed')),
      ),
    );

    await expectLater(
      () => resolver.resolve(RuntimeTarget.termux(), sshProfile: termuxProfile),
      throwsA(isA<StateError>()),
    );
  });

  test('termux without profile throws instead of native fallback', () async {
    final resolver = RuntimeContextResolver(
      nativeAppDataPath: tmp.path,
      nativeHome: tmp.path,
      nativeCwd: tmp.path,
    );

    await expectLater(
      () => resolver.resolve(RuntimeTarget.termux()),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Termux home requires'),
        ),
      ),
    );
  });

  test(
    'termux without ssh client factory throws instead of native fallback',
    () async {
      final resolver = RuntimeContextResolver(
        nativeAppDataPath: tmp.path,
        nativeHome: tmp.path,
        nativeCwd: tmp.path,
      );

      await expectLater(
        () =>
            resolver.resolve(RuntimeTarget.termux(), sshProfile: termuxProfile),
        throwsA(isA<StateError>()),
      );
    },
  );

  test('ssh target with no connection never resolves to a local fs', () async {
    final resolver = RuntimeContextResolver(
      nativeAppDataPath: tmp.path,
      nativeHome: tmp.path,
      nativeCwd: tmp.path,
    );

    // Degrading a remote machine to the phone's filesystem silently wrote to
    // the wrong device. Resolution must fail loudly instead.
    await expectLater(
      resolver.resolve(RuntimeTarget.ssh('p1', label: 'box')),
      throwsA(
        predicate<Object>(
          (error) =>
              error is StateError && error.message.contains('has no connection'),
        ),
      ),
    );
  });

  test('resolveCached ssh uses persisted paths without any network', () async {
    final factory = _MockSshClientFactory();
    // No stubbing: any factory/path-resolver call would throw and fail the
    // test, proving this path performs no network I/O.
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
      nativeAppDataPath: tmp.path,
      remotePathResolver: _FakePathResolver(
        clientFactory: factory,
        onResolve: (_) => Future.error(StateError('network must not be hit')),
      ),
    );

    final ctx = await resolver.resolveCached(
      RuntimeTarget.ssh('p1', label: 'Remote'),
      sshProfile: profile,
    );

    expect(ctx.target.kind, RuntimeKind.ssh);
    expect(ctx.mode, StorageBackendMode.ssh);
    expect(ctx.pathsFromCache, isTrue);
    expect(ctx.home, '/home/u');
    expect(ctx.appDataRoot, '/home/u/.local/share/com.hhoa.teampilot');
    verifyNever(() => factory.ensureStorageConnected(any()));
  });

  test('resolveCached ssh without cached paths returns the boot placeholder', () async {
    final resolver = RuntimeContextResolver(
      nativeAppDataPath: tmp.path,
      nativeHome: tmp.path,
      nativeCwd: tmp.path,
    );
    final ctx = await resolver.resolveCached(
      RuntimeTarget.ssh('p1', label: 'Remote'),
      sshProfile: const SshProfile(
        id: 'p1',
        name: 'Remote',
        host: 'example.com',
        username: 'u',
      ),
    );
    expect(ctx.pathsFromCache, isTrue);
    expect(ctx.mode, StorageBackendMode.native);
    expect(ctx.appDataRoot, tmp.path);
  });
}
