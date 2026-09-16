import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/services/ssh/mcp/session_ssh_mcp_constants.dart';
import 'package:teampilot/services/ssh/mcp/session_ssh_mcp_operations.dart';
import 'package:teampilot/services/ssh/mcp/session_ssh_mcp_paths.dart';
import 'package:teampilot/services/ssh/mcp/session_ssh_mcp_targets.dart';
import 'package:teampilot/services/ssh/ssh_storage_io.dart';

import '../../../support/in_memory_filesystem.dart';

SshProfile _profile(
  String id, {
  String? name,
  String host = '192.168.1.8',
  int port = 22,
  String username = 'alice',
}) {
  return SshProfile(
    id: id,
    name: name ?? id,
    host: host,
    port: port,
    username: username,
  );
}

void main() {
  late _FakeExecutor executor;
  late InMemoryFilesystem localFs;
  late SessionSshMcpOperations ops;

  final home = _profile('home', name: 'Home');
  final build = _profile(
    'build',
    name: 'Build',
    host: '10.0.0.2',
    port: 2222,
    username: 'ci',
  );

  SessionSshMcpTarget homeTarget({String folder = '/home/alice/proj'}) =>
      SessionSshMcpTarget(profile: home, folderPaths: [folder]);

  SessionSshMcpContext ctx({
    bool enabled = true,
    List<SessionSshMcpTarget>? targets,
    List<String> localAllowedRoots = const ['/workspace'],
  }) {
    return SessionSshMcpContext(
      enabled: enabled,
      targets: targets ?? [homeTarget()],
      localAllowedRoots: localAllowedRoots,
      localUsesPosixPaths: true,
      localFs: localFs,
    );
  }

  setUp(() {
    executor = _FakeExecutor();
    localFs = InMemoryFilesystem();
    ops = SessionSshMcpOperations(executor: executor);
  });

  group('disabled', () {
    test('returns ssh_mcp_disabled for every tool', () async {
      final disabled = ctx(enabled: false);
      final listed = await ops.listServers(disabled);
      final executed = await ops.executeCommand(disabled, {
        'cmdString': 'ls',
      });
      final uploaded = await ops.upload(disabled, {
        'localPath': '/workspace/a.txt',
        'remotePath': '/home/alice/proj/a.txt',
      });
      final downloaded = await ops.download(disabled, {
        'localPath': '/workspace/a.txt',
        'remotePath': '/home/alice/proj/a.txt',
      });

      for (final result in [listed, executed, uploaded, downloaded]) {
        expect(result.isError, isTrue);
        expect(result.code, sessionSshMcpErrorDisabled);
      }
      expect(executor.lastCommand, isNull);
    });
  });

  group('listServers', () {
    test('returns JSON list without password or privateKey fields', () async {
      final result = await ops.listServers(
        ctx(
          targets: [
            homeTarget(),
            SessionSshMcpTarget(
              profile: build,
              folderPaths: ['/opt/build', '/opt/cache'],
            ),
          ],
        ),
      );

      expect(result.isError, isFalse);
      final decoded = jsonDecode(result.text) as List<dynamic>;
      expect(decoded, [
        {
          'profileId': 'home',
          'name': 'Home',
          'host': '192.168.1.8',
          'port': 22,
          'username': 'alice',
          'folderPaths': ['/home/alice/proj'],
        },
        {
          'profileId': 'build',
          'name': 'Build',
          'host': '10.0.0.2',
          'port': 2222,
          'username': 'ci',
          'folderPaths': ['/opt/build', '/opt/cache'],
        },
      ]);
      for (final raw in decoded) {
        final map = raw as Map<String, dynamic>;
        expect(map.containsKey('password'), isFalse);
        expect(map.containsKey('privateKey'), isFalse);
        expect(map.keys.toSet(), {
          'profileId',
          'name',
          'host',
          'port',
          'username',
          'folderPaths',
        });
      }
    });
  });

  group('executeCommand', () {
    test('succeeds with one target when connectionName is omitted', () async {
      final result = await ops.executeCommand(ctx(), {'cmdString': 'ls'});

      expect(result.isError, isFalse);
      expect(executor.lastProfile?.id, 'home');
      expect(executor.lastTimeout, SshStorageIo.ioTimeout);
    });

    test('returns unknown_ssh_target when two targets omit name', () async {
      final result = await ops.executeCommand(
        ctx(
          targets: [
            homeTarget(),
            SessionSshMcpTarget(profile: build, folderPaths: ['/opt/build']),
          ],
        ),
        {'cmdString': 'ls'},
      );

      expect(result.isError, isTrue);
      expect(result.code, sessionSshMcpErrorUnknownTarget);
      expect(executor.lastCommand, isNull);
    });

    test('rejects cwd that escapes folder without calling executor', () async {
      final result = await ops.executeCommand(ctx(), {
        'cmdString': 'ls',
        'cwd': '/home/alice/proj/../secret',
      });

      expect(result.isError, isTrue);
      expect(result.code, sessionSshMcpErrorPath);
      expect(executor.lastCommand, isNull);
      expect(executor.lastProfile, isNull);
    });

    test('quotes cwd with sessionSshMcpPosixQuote and calls executor', () async {
      const folder = "/tmp/o'reilly";
      final result = await ops.executeCommand(
        ctx(targets: [homeTarget(folder: folder)]),
        {'cmdString': 'pwd', 'cwd': folder},
      );

      expect(result.isError, isFalse);
      expect(executor.lastProfile?.id, 'home');
      expect(
        executor.lastCommand,
        'cd -- ${sessionSshMcpPosixQuote(folder)} && pwd',
      );
    });

    test('maps TimeoutException to command_timeout', () async {
      executor.commandError = TimeoutException('slow');
      final result = await ops.executeCommand(ctx(), {'cmdString': 'sleep 9'});

      expect(result.isError, isTrue);
      expect(result.code, sessionSshMcpErrorTimeout);
    });

    test('returns OUTPUT_LIMIT_EXCEEDED with truncated text', () async {
      ops = SessionSshMcpOperations(executor: executor, maxOutputBytes: 8);
      executor.commandResult = (
        exitCode: 0,
        stdout: '12345',
        stderr: '67890',
      );

      final result = await ops.executeCommand(ctx(), {'cmdString': 'cat'});

      expect(result.isError, isTrue);
      expect(result.code, sessionSshMcpErrorOutputLimit);
      expect(result.text, '12345678');
    });

    test('rejects empty cmdString', () async {
      final empty = await ops.executeCommand(ctx(), {'cmdString': ''});
      final missing = await ops.executeCommand(ctx(), {});

      for (final result in [empty, missing]) {
        expect(result.isError, isTrue);
        expect(result.code, sessionSshMcpErrorInvalidParams);
        expect(result.text, 'cmdString is required');
        expect(result.code, isNot(sessionSshMcpErrorUnknownTarget));
        expect(result.code, isNot(sessionSshMcpErrorPath));
      }
      expect(executor.lastCommand, isNull);
    });

    test('sanitizes executor throw on execute', () async {
      executor.commandError = Exception('leaked secret token');
      final result = await ops.executeCommand(ctx(), {'cmdString': 'ls'});

      expect(result.isError, isTrue);
      expect(result.code, sessionSshMcpErrorUnavailable);
      expect(result.text, isNot(contains('secret')));
    });
  });

  group('upload and download', () {
    test('rejects missing local file under root', () async {
      final result = await ops.upload(ctx(), {
        'localPath': '/workspace/missing.txt',
        'remotePath': '/home/alice/proj/a.txt',
      });

      expect(result.isError, isTrue);
      expect(result.code, sessionSshMcpErrorPath);
      expect(executor.lastRemotePath, isNull);
      expect(executor.lastUploadedBytes, isNull);
    });

    test('rejects symlink under root pointing outside without calling executor', () async {
      await localFs.writeBytes('/outside/secret.txt', [9, 9, 9]);
      await localFs.createSymlink(
        target: '/outside/secret.txt',
        linkPath: '/workspace/link.txt',
      );

      final result = await ops.upload(ctx(), {
        'localPath': '/workspace/link.txt',
        'remotePath': '/home/alice/proj/a.txt',
      });

      expect(result.isError, isTrue);
      expect(result.code, sessionSshMcpErrorPath);
      expect(executor.lastRemotePath, isNull);
      expect(executor.lastUploadedBytes, isNull);
    });

    test('upload succeeds inside roots', () async {
      await localFs.writeBytes('/workspace/a.txt', [1, 2, 3]);

      final result = await ops.upload(ctx(), {
        'localPath': '/workspace/a.txt',
        'remotePath': '/home/alice/proj/a.txt',
      });

      expect(result.isError, isFalse);
      expect(executor.lastProfile?.id, 'home');
      expect(executor.lastRemotePath, '/home/alice/proj/a.txt');
      expect(executor.lastUploadedBytes, [1, 2, 3]);
    });

    test('download succeeds inside roots', () async {
      executor.remoteFiles['/home/alice/proj/b.txt'] = [9, 8, 7];

      final result = await ops.download(ctx(), {
        'localPath': '/workspace/out/b.txt',
        'remotePath': '/home/alice/proj/b.txt',
      });

      expect(result.isError, isFalse);
      expect(await localFs.readBytes('/workspace/out/b.txt'), [9, 8, 7]);
    });

    test('rejects ../ on local or remote paths', () async {
      await localFs.writeBytes('/workspace/a.txt', [1]);

      final localEscape = await ops.upload(ctx(), {
        'localPath': '/workspace/../secret.txt',
        'remotePath': '/home/alice/proj/a.txt',
      });
      final remoteEscape = await ops.upload(ctx(), {
        'localPath': '/workspace/a.txt',
        'remotePath': '/home/alice/proj/../secret.txt',
      });
      final downloadLocal = await ops.download(ctx(), {
        'localPath': '/workspace/../out.txt',
        'remotePath': '/home/alice/proj/a.txt',
      });
      final downloadRemote = await ops.download(ctx(), {
        'localPath': '/workspace/out.txt',
        'remotePath': '/home/alice/proj/../secret.txt',
      });

      for (final result in [
        localEscape,
        remoteEscape,
        downloadLocal,
        downloadRemote,
      ]) {
        expect(result.isError, isTrue);
        expect(result.code, sessionSshMcpErrorPath);
      }
      expect(executor.lastRemotePath, isNull);
    });

    test('sanitizes executor throw on upload and download', () async {
      await localFs.writeBytes('/workspace/a.txt', [1]);
      executor.sftpError = Exception('sftp secret leaked');

      final uploaded = await ops.upload(ctx(), {
        'localPath': '/workspace/a.txt',
        'remotePath': '/home/alice/proj/a.txt',
      });
      final downloaded = await ops.download(ctx(), {
        'localPath': '/workspace/b.txt',
        'remotePath': '/home/alice/proj/a.txt',
      });

      for (final result in [uploaded, downloaded]) {
        expect(result.isError, isTrue);
        expect(result.code, sessionSshMcpErrorSftp);
        expect(result.text, isNot(contains('secret')));
      }
    });
  });
}

class _FakeExecutor implements SessionSshMcpExecutor {
  SshProfile? lastProfile;
  String? lastCommand;
  Duration? lastTimeout;
  String? lastRemotePath;
  List<int>? lastUploadedBytes;

  Object? commandError;
  ({int? exitCode, String stdout, String stderr}) commandResult = (
    exitCode: 0,
    stdout: 'ok',
    stderr: '',
  );

  Object? sftpError;
  final Map<String, List<int>> remoteFiles = {};

  @override
  Future<({int? exitCode, String stdout, String stderr})> runCommand({
    required SshProfile profile,
    required String command,
    required Duration timeout,
  }) async {
    lastProfile = profile;
    lastCommand = command;
    lastTimeout = timeout;
    if (commandError != null) {
      throw commandError!;
    }
    return commandResult;
  }

  @override
  Future<void> upload({
    required SshProfile profile,
    required List<int> bytes,
    required String remotePath,
  }) async {
    lastProfile = profile;
    lastRemotePath = remotePath;
    lastUploadedBytes = bytes;
    if (sftpError != null) {
      throw sftpError!;
    }
    remoteFiles[remotePath] = List<int>.from(bytes);
  }

  @override
  Future<List<int>> download({
    required SshProfile profile,
    required String remotePath,
  }) async {
    lastProfile = profile;
    lastRemotePath = remotePath;
    if (sftpError != null) {
      throw sftpError!;
    }
    return remoteFiles[remotePath] ?? const <int>[];
  }
}
