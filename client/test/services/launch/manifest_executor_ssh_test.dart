import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/ssh_known_host_repository.dart';
import 'package:teampilot/services/launch/launch_manifest.dart';
import 'package:teampilot/services/launch/manifest_executor.dart';
import 'package:teampilot/services/ssh/ssh_client_factory.dart';
import 'package:teampilot/utils/logging/logger.dart';

import '../../support/in_memory_filesystem.dart';

class _RecordedExec {
  const _RecordedExec({required this.command, this.stdin});

  final String command;
  final List<int>? stdin;
}

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

    final fs = InMemoryFilesystem();
    final manifest = LaunchManifest()..writeFile('/tmp/cursor/settings.json', '{}');
    final executor = ManifestExecutor(
      sshClientFactory: factory,
      profileById: (_) => profile,
    );

    await executor.flush(
      manifest: manifest,
      targetFs: fs,
      sourceFs: fs,
      sshProfileId: profile.id,
    );

    expect(createCount, 1);
    expect(factory.hasLiveStorageClient(profile.id), isTrue);
  });

  test('same-host ssh flush runs remote cp without expanding copies', () async {
    final execs = <_RecordedExec>[];
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
          onRun: (command, stdin) {
            execs.add(_RecordedExec(command: command, stdin: stdin));
          },
        );
      },
    );

    final fs = InMemoryFilesystem();
    final manifest = LaunchManifest()
      ..copyTree(source: '/src/tree', destination: '/dst/tree')
      ..symlink(linkPath: '/dst/home/.npm', target: '/root/.npm');

    final before = await appLogger.getPendingLogLines();
    await ManifestExecutor(
      sshClientFactory: factory,
      profileById: (_) => profile,
    ).flush(
      manifest: manifest,
      targetFs: fs,
      sourceFs: fs,
      sshProfileId: profile.id,
    );
    final lines = (await appLogger.getPendingLogLines()).skip(before.length);

    expect(execs, hasLength(1));
    expect(execs.single.command, 'bash -s');
    final script = utf8.decode(execs.single.stdin!);
    expect(script, contains("cp -R -- '/src/tree/.' '/dst/tree'"));
    expect(script, contains("rm -rf -- '/dst/home/.npm'"));
    expect(script, contains("ln -sfn -- '/root/.npm' '/dst/home/.npm'"));
    expect(script, isNot(contains('cat >')));
    expect(
      lines.where((l) => l.contains('[session-launch] manifest flush via ssh ops=')),
      isNotEmpty,
    );
    expect(
      lines.where(
        (l) =>
            l.contains('stdinBytes=') &&
            l.contains('scriptEpochs=') &&
            l.contains('tarEpochs='),
      ),
      isNotEmpty,
    );
  });

  test('off-home ssh flush rejects empty work root', () async {
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
        return _RunnableClient();
      },
    );
    await expectLater(
      ManifestExecutor(
        sshClientFactory: factory,
        profileById: (_) => profile,
      ).flush(
        manifest: LaunchManifest()..writeFile('/tmp/a.txt', 'x'),
        targetFs: InMemoryFilesystem(),
        sourceFs: InMemoryFilesystem(),
        sshProfileId: profile.id,
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('work app-data root'),
        ),
      ),
    );
  });

  test('cross-machine ssh flush copies external symlink targets', () async {
    final execs = <_RecordedExec>[];
    const profile = SshProfile(
      id: 'p1',
      name: 'dev',
      host: 'example.com',
      username: 'alice',
    );
    const workRoot = '/home/alice/.local/share/teampilot';
    final factory = SshClientFactory(
      credentialStore: InMemorySshCredentialStore(),
      knownHostRepository: InMemorySshKnownHostRepository(),
      connector: (profile, {timeout = const Duration(seconds: 10)}) async {
        return _RunnableClient(
          onRun: (command, stdin) {
            execs.add(_RecordedExec(command: command, stdin: stdin));
          },
        );
      },
    );
    final source = InMemoryFilesystem();
    final target = InMemoryFilesystem();
    await source.writeString('/home/alice/.claude.json', 'credentials');
    final manifest = LaunchManifest()
      ..symlink(
        linkPath: '$workRoot/.config/claude.json',
        target: '/home/alice/.claude.json',
      );

    await ManifestExecutor(
      sshClientFactory: factory,
      profileById: (_) => profile,
    ).flush(
      manifest: manifest,
      targetFs: target,
      sourceFs: source,
      symlinkProjectionRoot: workRoot,
      sshProfileId: profile.id,
    );

    expect(execs, hasLength(1));
    expect(
      execs.single.command,
      "mkdir -p '$workRoot' && gzip -dc | tar -x -C '$workRoot'",
    );
    final stdin = execs.single.stdin!;
    expect(stdin.length, greaterThan(2));
    expect(stdin[0], 0x1f);
    expect(stdin[1], 0x8b);
    final scriptText = utf8.decode(stdin, allowMalformed: true);
    expect(scriptText, isNot(contains('credentials')));
    final tar = GZipDecoder().decodeBytes(stdin);
    final decoded = TarDecoder().decodeBytes(tar);
    final file = decoded.findFile('.config/claude.json')!;
    expect(utf8.decode(file.content as List<int>), 'credentials');
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

  final void Function(String command, List<int>? stdin)? onRun;

  @override
  Future<void> get authenticated => Future.value();

  @override
  Future<SSHRunResult> runWithResult(
    String command, {
    bool runInPty = false,
    bool stdout = true,
    bool stderr = true,
    Map<String, String>? environment,
    List<int>? stdin,
  }) async {
    onRun?.call(command, stdin);
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
