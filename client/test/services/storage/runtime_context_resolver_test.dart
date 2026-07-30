import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
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

class _MockSftpClient extends Mock implements SftpClient {}

class _FakePathResolver extends RemoteSshStoragePathResolver {
  _FakePathResolver({
    required SshClientFactory clientFactory,
    required this.onResolve,
  }) : super(clientFactory: clientFactory);

  final Future<RemoteSshStoragePaths> Function(SshProfile profile) onResolve;

  @override
  Future<RemoteSshStoragePaths> resolve(SshProfile profile) => onResolve(profile);
}

void main() {
  late Directory tmp;
  late SshProfile termuxProfile;

  setUpAll(() {
    registerFallbackValue(
      const SshProfile(id: 'termux', name: 'Termux', host: '127.0.0.1', username: 'u'),
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
    final sftp = _MockSftpClient();
    when(() => factory.sftpFor(any())).thenAnswer((_) async => sftp);

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
    verify(() => factory.sftpFor(termuxProfile)).called(1);
  });

  test('termux SFTP failure with cached paths falls back without throwing', () async {
    final factory = _MockSshClientFactory();
    when(() => factory.sftpFor(any())).thenThrow(StateError('sshd down'));

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
    expect(ctx.home, '/data/data/com.termux/files/home');
    expect(
      ctx.appDataRoot,
      '/data/data/com.termux/files/home/.local/share/com.hhoa.teampilot',
    );
  });

  test('termux failure without cache rethrows', () async {
    final factory = _MockSshClientFactory();
    when(() => factory.sftpFor(any())).thenThrow(StateError('sshd down'));

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
        RuntimeTarget.termux(),
        sshProfile: termuxProfile,
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('ssh target with no profile falls back to native', () async {
    final resolver = RuntimeContextResolver(
      nativeAppDataPath: tmp.path,
      nativeHome: tmp.path,
      nativeCwd: tmp.path,
    );
    final ctx = await resolver.resolve(RuntimeTarget.ssh('p1', label: 'box'));
    expect(ctx.appDataRoot, tmp.path);
    expect(ctx.usesPosixPaths, isFalse);
  });
}
