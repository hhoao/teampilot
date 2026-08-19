import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/ssh_known_host_repository.dart';
import 'package:teampilot/services/launch/launch_manifest.dart';
import 'package:teampilot/services/launch/manifest_executor.dart';
import 'package:teampilot/services/ssh/ssh_client_factory.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  test('ssh manifest flush keeps storage pool alive', () async {
    var createCount = 0;
    const profile = SshProfile(
      id: 'p1',
      name: 'dev',
      host: 'example.com',
      username: 'alice',
    );

    final factory = SshClientFactory(
      credentialStore: InMemorySshCredentialStore(),
      knownHostRepository: InMemorySshKnownHostRepository(),
      connector: (profile, {timeout = const Duration(seconds: 10)}) async {
        createCount += 1;
        return _RunnableClient();
      },
    );

    await factory.clientForStorage(profile);
    expect(factory.hasLiveStorageClient(profile.id), isTrue);
    expect(createCount, 1);

    final manifest = LaunchManifest()..writeFile('/tmp/cursor/settings.json', '{}');
    final executor = ManifestExecutor(
      sshClientFactory: factory,
      profileById: (_) => profile,
    );

    await executor.flush(
      manifest: manifest,
      targetFs: InMemoryFilesystem(),
      sourceFs: InMemoryFilesystem(),
      sshProfileId: profile.id,
    );

    expect(createCount, 1);
    expect(factory.hasLiveStorageClient(profile.id), isTrue);
  });

  test('same-host ssh flush runs remote cp without expanding copies', () async {
    String? ranScript;
    const profile = SshProfile(
      id: 'p1',
      name: 'dev',
      host: 'example.com',
      username: 'alice',
    );

    final factory = SshClientFactory(
      credentialStore: InMemorySshCredentialStore(),
      knownHostRepository: InMemorySshKnownHostRepository(),
      connector: (profile, {timeout = const Duration(seconds: 10)}) async {
        return _RunnableClient(
          onRun: (command) {
            ranScript = command;
          },
        );
      },
    );

    final fs = InMemoryFilesystem();
    final manifest = LaunchManifest()
      ..copyTree(source: '/src/tree', destination: '/dst/tree')
      ..symlink(linkPath: '/dst/home/.npm', target: '/root/.npm');

    await ManifestExecutor(
      sshClientFactory: factory,
      profileById: (_) => profile,
    ).flush(
      manifest: manifest,
      targetFs: fs,
      sourceFs: fs,
      sshProfileId: profile.id,
    );

    expect(ranScript, isNotNull);
    expect(ranScript, contains("cp -R -- '/src/tree/.' '/dst/tree'"));
    expect(
      ranScript,
      contains("rm -rf -- '/dst/home/.npm'"),
    );
    expect(
      ranScript,
      contains("ln -sfn -- '/root/.npm' '/dst/home/.npm'"),
    );
    expect(ranScript, isNot(contains('cat >')));
  });

  test(
    'ssh symlink apply replaces leftover Codex plugins directory',
    () async {
      if (Platform.isWindows) return;

      final tmp = await Directory.systemTemp.createTemp('tp_manifest_ln_');
      addTearDown(() async {
        if (await tmp.exists()) await tmp.delete(recursive: true);
      });

      final sharedPlugins = p.join(
        tmp.path,
        'cli-defaults',
        'codex',
        '.tmp',
        'plugins',
      );
      final sessionPlugins = p.join(
        tmp.path,
        'workspace',
        'sessions',
        's1',
        'runtime',
        'codex',
        '.tmp',
        'plugins',
      );
      await Directory(sharedPlugins).create(recursive: true);
      await File(p.join(sharedPlugins, 'stamp')).writeAsString('shared');
      // Previous copyTree / nested `ln -sf` left a real dir at the link path
      // and another `plugins` dir inside it — GNU ln then errors with
      // "cannot overwrite directory".
      await Directory(p.join(sessionPlugins, 'plugins')).create(recursive: true);

      final script = ManifestExecutor.debugBuildApplyScript(
        LaunchManifest()
          ..symlink(linkPath: sessionPlugins, target: sharedPlugins),
      );
      final result = await Process.run('bash', ['-c', script]);
      expect(
        result.exitCode,
        0,
        reason: 'stderr=${result.stderr}\nstdout=${result.stdout}',
      );
      expect(
        FileSystemEntity.typeSync(sessionPlugins, followLinks: false),
        FileSystemEntityType.link,
      );
      expect(Link(sessionPlugins).targetSync(), sharedPlugins);
    },
  );
}

class _RunnableClient extends SSHClient {
  _RunnableClient({this.onRun}) : super(_FakeSSHSocket(), username: 'test');

  final void Function(String command)? onRun;

  @override
  Future<void> get authenticated => Future.value();

  @override
  Future<SSHRunResult> runWithResult(
    String command, {
    bool runInPty = false,
    bool stdout = true,
    bool stderr = true,
    Map<String, String>? environment,
  }) async {
    onRun?.call(command);
    return SSHRunResult(
      output: Uint8List(0),
      stdout: Uint8List(0),
      stderr: Uint8List(0),
      exitCode: 0,
      exitSignal: null,
    );
  }

  @override
  Future<void> ping() async {}
}

class _FakeSSHSocket implements SSHSocket {
  final _inputController = StreamController<Uint8List>();
  final _doneCompleter = Completer<void>();

  @override
  Stream<Uint8List> get stream => _inputController.stream;

  @override
  StreamSink<List<int>> get sink => _NoopSink();

  @override
  Future<void> get done => _doneCompleter.future;

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {
    if (!_doneCompleter.isCompleted) {
      _doneCompleter.complete();
    }
    await _inputController.close();
  }

  @override
  void destroy() {
    if (!_doneCompleter.isCompleted) {
      _doneCompleter.complete();
    }
    unawaited(_inputController.close());
  }
}

class _NoopSink implements StreamSink<List<int>> {
  @override
  void add(List<int> data) {}

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final _ in stream) {}
  }

  @override
  Future<void> close() async {}

  @override
  Future<void> get done async {}
}
