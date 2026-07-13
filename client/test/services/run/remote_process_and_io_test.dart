import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/run/launch_configuration.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/services/run/launch_config_store.dart';
import 'package:teampilot/services/run/process_run_executor.dart';
import 'package:teampilot/services/run/run_target_resolver.dart';

import '../../support/in_memory_filesystem.dart';

class FakeProcessHandle implements ProcessRunHandle {
  FakeProcessHandle({
    required this.exitCode,
    Stream<List<int>>? stdout,
    Stream<List<int>>? stderr,
    this.onKill,
  }) : stdout = stdout ?? const Stream.empty(),
       stderr = stderr ?? const Stream.empty();

  @override
  final Future<int> exitCode;

  @override
  final Stream<List<int>> stdout;

  @override
  final Stream<List<int>> stderr;

  final void Function()? onKill;

  @override
  void kill() => onKill?.call();
}

class RecordingSpawner {
  String? lastExecutable;
  List<String>? lastArguments;
  String? lastWorkingDirectory;
  bool? lastRunInShell;

  Future<ProcessRunHandle> call({
    required String executable,
    required List<String> arguments,
    required String workingDirectory,
    Map<String, String>? environment,
    bool runInShell = false,
    bool includeParentEnvironment = true,
  }) async {
    lastExecutable = executable;
    lastArguments = arguments;
    lastWorkingDirectory = workingDirectory;
    lastRunInShell = runInShell;
    return FakeProcessHandle(exitCode: Future.value(0));
  }
}

class RecordingSshSpawner {
  String? lastProfileId;
  String? lastShellCommand;

  Future<ProcessRunHandle> call({
    required String sshProfileId,
    required String shellCommand,
  }) async {
    lastProfileId = sshProfileId;
    lastShellCommand = shellCommand;
    return FakeProcessHandle(
      exitCode: Future.value(0),
      stdout: Stream.value(utf8.encode('remote-ok\n')),
    );
  }
}

void main() {
  group('ProcessRunExecutor remote transport', () {
    test('spawns wsl.exe argv for wsl plan', () async {
      final spawner = RecordingSpawner();
      final exec = ProcessRunExecutor(spawner: spawner);
      final plan = RunTargetPlan(
        workingDirectory: '/home/user/proj',
        runtimeTarget: RuntimeTarget.wsl('Ubuntu'),
        targetId: 'wsl:Ubuntu',
        useWslPaths: true,
      );

      final result = await exec.start(
        sessionId: 's1',
        command: 'npm',
        args: const ['run', 'dev'],
        plan: plan,
        onOutput: (_) {},
      );

      expect(await result.exitCode, 0);
      expect(spawner.lastExecutable, 'wsl.exe');
      expect(
        spawner.lastArguments,
        containsAll([
          '-d',
          'Ubuntu',
          '--cd',
          '/home/user/proj',
          'npm',
          'run',
          'dev',
        ]),
      );
      expect(spawner.lastRunInShell, isFalse);
    });

    test('uses injected ssh spawner for ssh plan', () async {
      final ssh = RecordingSshSpawner();
      final exec = ProcessRunExecutor(sshSpawner: ssh.call);
      final plan = RunTargetPlan(
        workingDirectory: '/remote/proj',
        runtimeTarget: RuntimeTarget.ssh('profile-1', label: 'box'),
        targetId: 'ssh:profile-1',
        useWslPaths: false,
      );
      final outputs = <ProcessRunOutput>[];

      final result = await exec.start(
        sessionId: 's1',
        command: 'echo',
        args: const ['hi'],
        plan: plan,
        env: const {'FOO': 'bar'},
        onOutput: outputs.add,
      );

      expect(await result.exitCode, 0);
      expect(ssh.lastProfileId, 'profile-1');
      expect(ssh.lastShellCommand, contains("cd '/remote/proj'"));
      expect(ssh.lastShellCommand, contains("export 'FOO'='bar'"));
      expect(ssh.lastShellCommand, contains("'echo' 'hi'"));
      await Future<void>.delayed(Duration.zero);
      expect(outputs.single.data, 'remote-ok\n');
    });

    test('ssh plan without spawner throws StateError', () async {
      final exec = ProcessRunExecutor(spawner: RecordingSpawner().call);
      final plan = RunTargetPlan(
        workingDirectory: '/remote/proj',
        runtimeTarget: RuntimeTarget.ssh('profile-1', label: ''),
        targetId: 'ssh:profile-1',
        useWslPaths: false,
      );
      await expectLater(
        exec.start(
          sessionId: 's1',
          command: 'true',
          args: const [],
          plan: plan,
          onOutput: (_) {},
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('TargetAwareLaunchConfigIo', () {
    test('routes read/write by folder targetId', () async {
      final localFs = InMemoryFilesystem();
      final sshFs = InMemoryFilesystem();
      final io = TargetAwareLaunchConfigIo(
        resolveFilesystem: (targetId) async {
          if (targetId.startsWith('ssh:')) return sshFs;
          return localFs;
        },
      );
      final store = LaunchConfigStore(io: io);
      const localFolder = WorkspaceFolder(path: '/local', targetId: 'local');
      const sshFolder = WorkspaceFolder(
        path: '/remote',
        targetId: 'ssh:profile-1',
      );

      await store.upsertConfiguration(
        folder: localFolder,
        configuration: const LaunchConfiguration(
          id: 'local-run',
          name: 'Local',
          type: 'shellScript',
          extras: {
            'execute': 'scriptText',
            'scriptText': 'echo',
          },
        ),
      );
      await store.upsertConfiguration(
        folder: sshFolder,
        configuration: const LaunchConfiguration(
          id: 'ssh-run',
          name: 'SSH',
          type: 'shellScript',
          extras: {
            'execute': 'scriptText',
            'scriptText': 'echo',
          },
        ),
      );

      expect(
        await localFs.readString('/local/.teampilot/launch.json'),
        isNotNull,
      );
      expect(
        await sshFs.readString('/remote/.teampilot/launch.json'),
        isNotNull,
      );
      expect(await localFs.readString('/remote/.teampilot/launch.json'), isNull);
      expect(await sshFs.readString('/local/.teampilot/launch.json'), isNull);

      final listed = await store.listConfigurations(
        folders: [localFolder, sshFolder],
      );
      expect(listed.map((e) => e.configuration.id).toSet(), {
        'local-run',
        'ssh-run',
      });
    });
  });
}
