import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/services/host/process_run_handle.dart';
import 'package:teampilot/services/run/process_run_executor.dart';
import 'package:teampilot/services/run/run_target_resolver.dart';

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

class FakeSpawner {
  String? lastExecutable;
  List<String>? lastArguments;
  String? lastWorkingDirectory;
  Map<String, String>? lastEnvironment;
  bool? lastRunInShell;

  int exitCode = 0;
  Stream<List<int>>? stdout;
  Stream<List<int>>? stderr;
  var killCount = 0;

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
    lastEnvironment = environment;
    lastRunInShell = runInShell;
    return FakeProcessHandle(
      exitCode: Future.value(exitCode),
      stdout: stdout,
      stderr: stderr,
      onKill: () => killCount++,
    );
  }
}

RunTargetPlan get localPlan => RunTargetPlan(
  workingDirectory: '/proj',
  runtimeTarget: RuntimeTarget.local(),
  targetId: WorkspaceFolder.localTargetId,
  useWslPaths: false,
);

void main() {
  test('process executor runs command and reports exit 0', () async {
    final spawner = FakeSpawner();
    final exec = ProcessRunExecutor(spawner: spawner);
    final result = await exec.start(
      sessionId: 's1',
      command: 'true',
      args: const [],
      plan: localPlan,
      onOutput: (_) {},
    );
    expect(await result.exitCode, 0);
    expect(spawner.lastExecutable, 'true');
    expect(spawner.lastArguments, isEmpty);
    expect(spawner.lastWorkingDirectory, '/proj');
  });

  test('process executor forwards stdout output', () async {
    final spawner = FakeSpawner()
      ..stdout = Stream.value(utf8.encode('hello\n'));
    final exec = ProcessRunExecutor(spawner: spawner);
    final outputs = <ProcessRunOutput>[];
    await exec.start(
      sessionId: 's1',
      command: 'echo',
      args: const ['hi'],
      plan: localPlan,
      onOutput: outputs.add,
    );
    await Future<void>.delayed(Duration.zero);
    expect(outputs, hasLength(1));
    expect(outputs.single.sessionId, 's1');
    expect(outputs.single.category, 'stdout');
    expect(outputs.single.data, 'hello\n');
  });

  test('process executor stop kills the process', () async {
    final spawner = FakeSpawner();
    final exec = ProcessRunExecutor(spawner: spawner);
    final result = await exec.start(
      sessionId: 's1',
      command: 'sleep',
      args: const ['60'],
      plan: localPlan,
      onOutput: (_) {},
    );
    await result.stop();
    expect(spawner.killCount, 1);
  });
}
