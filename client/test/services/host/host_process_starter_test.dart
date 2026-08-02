import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/host/host_one_shot_runner.dart';
import 'package:teampilot/services/host/host_process_starter.dart';
import 'package:teampilot/services/host/host_process_starter_for_context.dart';
import 'package:teampilot/services/host/process_run_handle.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/storage/app_storage.dart';

class _FakeProcessRunHandle implements ProcessRunHandle {
  @override
  Future<int> get exitCode => Future.value(0);

  @override
  Stream<List<int>> get stderr => const Stream.empty();

  @override
  Stream<List<int>> get stdout => const Stream.empty();

  @override
  void kill() {}
}

void main() {
  group('LocalHostProcessStarter', () {
    test('starts executable with argv via injectable spawner', () async {
      final calls = <Map<String, Object?>>[];
      final starter = LocalHostProcessStarter(
        spawner:
            ({
              required executable,
              required arguments,
              workingDirectory,
              environment,
              includeParentEnvironment = true,
            }) async {
              calls.add({
                'executable': executable,
                'arguments': arguments,
                'workingDirectory': workingDirectory,
                'environment': environment,
                'includeParentEnvironment': includeParentEnvironment,
              });
              return _FakeProcessRunHandle();
            },
      );

      await starter.start(
        const HostRunRequest(
          executable: 'echo',
          arguments: ['hi'],
          workingDirectory: '/tmp',
        ),
      );

      expect(calls.single['executable'], 'echo');
      expect(calls.single['arguments'], ['hi']);
      expect(calls.single['workingDirectory'], '/tmp');
    });
  });

  group('WslHostProcessStarter', () {
    test('prefixes wsl.exe argv with distro and inner command', () async {
      final calls = <List<String>>[];
      final starter = WslHostProcessStarter(
        distro: 'Ubuntu',
        spawner:
            ({
              required executable,
              required arguments,
              workingDirectory,
              environment,
              includeParentEnvironment = true,
            }) async {
              calls.add([executable, ...arguments]);
              return _FakeProcessRunHandle();
            },
      );

      await starter.start(
        HostRunRequest(
          executable: 'git',
          arguments: ['status'],
          workingDirectory: '/home/user/repo',
        ),
      );

      expect(
        calls.single,
        containsAll([
          'wsl.exe',
          '-d',
          'Ubuntu',
          '--cd',
          '/home/user/repo',
          'git',
          'status',
        ]),
      );
    });
  });

  group('RemoteHostProcessStarter', () {
    test('shell-quotes argv for startShell', () async {
      final commands = <String>[];
      final starter = RemoteHostProcessStarter(
        startShell: (cmd) async {
          commands.add(cmd);
          return _FakeProcessRunHandle();
        },
      );

      await starter.start(
        HostRunRequest(
          executable: 'git',
          arguments: ['-C', '/repo/with spaces', 'status'],
        ),
      );

      expect(commands.single, contains("'-C' '/repo/with spaces'"));
      expect(commands.single, endsWith("'status'"));
    });
  });

  group('hostProcessStarterForContext', () {
    test('picks local starter for native storage', () {
      AppStorage.installForTesting(
        filesystem: LocalFilesystem(),
        paths: AppPaths('/tmp/teampilot-test'),
        home: '/tmp',
        cwd: '/tmp',
      );
      addTearDown(AppStorage.resetForTesting);

      expect(
        hostProcessStarterForContext(AppStorage.context),
        isA<LocalHostProcessStarter>(),
      );
    });
  });
}
