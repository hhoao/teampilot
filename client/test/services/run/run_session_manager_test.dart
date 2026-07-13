import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/run/launch_config_document.dart';
import 'package:teampilot/models/run/launch_configuration.dart';
import 'package:teampilot/models/run/run_session.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/services/run/process_run_executor.dart';
import 'package:teampilot/services/run/run_session_manager.dart';

const _folder = WorkspaceFolder(path: '/proj');

OwnedLaunchConfiguration ownedConfig({
  required String id,
  String command = 'true',
  bool executeInTerminal = false,
}) {
  return OwnedLaunchConfiguration(
    owner: _folder,
    configuration: LaunchConfiguration(
      id: id,
      name: id,
      type: 'shellScript',
      extras: {
        'execute': 'scriptText',
        'scriptText': command,
        'executeInTerminal': executeInTerminal,
      },
    ),
  );
}

class FakeRunExecutor implements RunProcessLauncher {
  FakeRunExecutor({
    this.hangOnStart = false,
    this.blockStartUntilReleased = false,
    this.exitCode = 0,
    Set<String>? failStartForConfigIds,
  }) : failStartForConfigIds = failStartForConfigIds ?? {},
       _startBlocker = blockStartUntilReleased ? Completer<void>() : null;

  final bool hangOnStart;
  final bool blockStartUntilReleased;
  final int exitCode;
  final Set<String> failStartForConfigIds;
  final startedSessionIds = <String>[];
  final preferredTerminalEntryIds = <String?>[];
  final Completer<void>? _startBlocker;
  var stopCount = 0;
  var concurrentLaunches = 0;
  var maxConcurrentLaunches = 0;

  void releaseStart() {
    _startBlocker?.complete();
  }

  @override
  Future<RunLaunchHandle> launch({
    required String sessionId,
    required OwnedLaunchConfiguration owned,
    required void Function(ProcessRunOutput output) onOutput,
    String? preferTerminalEntryId,
  }) async {
    preferredTerminalEntryIds.add(preferTerminalEntryId);
    if (failStartForConfigIds.contains(owned.configId)) {
      throw StateError('failed to start ${owned.configId}');
    }

    concurrentLaunches++;
    maxConcurrentLaunches = concurrentLaunches > maxConcurrentLaunches
        ? concurrentLaunches
        : maxConcurrentLaunches;

    if (_startBlocker != null) {
      await _startBlocker.future;
    }

    startedSessionIds.add(sessionId);

    if (hangOnStart) {
      final exitCompleter = Completer<int>();
      return RunLaunchHandle(
        exitCode: exitCompleter.future,
        stop: () async {
          stopCount++;
          if (!exitCompleter.isCompleted) {
            exitCompleter.complete(130);
          }
        },
      );
    }

    return RunLaunchHandle(
      exitCode: Future.value(exitCode),
      stop: () async {
        stopCount++;
      },
    );
  }
}

RunAdapterLauncher get noopAdapter => const _NoopAdapter();

class _NoopAdapter implements RunAdapterLauncher {
  const _NoopAdapter();

  @override
  Future<RunLaunchHandle> launch({
    required String sessionId,
    required OwnedLaunchConfiguration owned,
    required void Function(ProcessRunOutput output) onOutput,
  }) {
    throw UnimplementedError('Launch adapter: Task 6');
  }
}

void main() {
  test('hasRunning treats starting as occupied', () async {
    final executor = FakeRunExecutor(
      blockStartUntilReleased: true,
      hangOnStart: true,
    );
    final mgr = RunSessionManager(executor: executor, adapters: noopAdapter);
    final owned = ownedConfig(id: 'a');
    unawaited(mgr.start(owned));
    await Future<void>.delayed(Duration.zero);
    expect(mgr.hasRunning(owned.selectionKey), isTrue);
    expect(mgr.sessions.single.status, RunSessionStatus.starting);

    executor.releaseStart();
    await Future<void>.delayed(Duration.zero);
    final sessionId = mgr.sessions.single.id;
    await mgr.stop(sessionId);
    await mgr.dispose();
  });

  test('sessionsStream emits on start and stop', () async {
    final executor = FakeRunExecutor(hangOnStart: true);
    final mgr = RunSessionManager(executor: executor, adapters: noopAdapter);
    final emissions = <List<RunSession>>[];
    final sub = mgr.sessionsStream.listen(emissions.add);
    await Future<void>.delayed(Duration.zero);

    final s = await mgr.start(ownedConfig(id: 'a'));
    await Future<void>.delayed(Duration.zero);
    expect(emissions.length, greaterThanOrEqualTo(2));
    expect(emissions.first.single.status, RunSessionStatus.starting);
    expect(emissions.last.single.status, RunSessionStatus.running);

    await mgr.stop(s.id);
    await Future<void>.delayed(Duration.zero);
    expect(emissions.last.single.status, RunSessionStatus.exited);

    await sub.cancel();
    await mgr.dispose();
  });

  test('stop during start does not promote to running', () async {
    final executor = FakeRunExecutor(blockStartUntilReleased: true);
    final mgr = RunSessionManager(executor: executor, adapters: noopAdapter);
    final owned = ownedConfig(id: 'a');

    final startFuture = mgr.start(owned);
    await Future<void>.delayed(Duration.zero);

    final sessionId = mgr.sessions.single.id;
    expect(mgr.session(sessionId)?.status, RunSessionStatus.starting);

    await mgr.stop(sessionId);
    expect(mgr.session(sessionId)?.status, RunSessionStatus.exited);

    executor.releaseStart();
    final result = await startFuture;

    expect(result.status, RunSessionStatus.exited);
    expect(mgr.hasRunning(owned.selectionKey), isFalse);
    expect(executor.stopCount, 1);
    await mgr.dispose();
  });

  test('startCompound launches members concurrently', () async {
    final executor = FakeRunExecutor(blockStartUntilReleased: true);
    final mgr = RunSessionManager(executor: executor, adapters: noopAdapter);
    final compound = const LaunchCompound(
      id: 'all',
      name: 'All',
      configurationIds: ['a', 'b'],
    );
    final configs = [
      ownedConfig(id: 'a'),
      ownedConfig(id: 'b'),
    ];

    final compoundFuture = mgr.startCompound(
      compound: compound,
      documentConfigs: configs,
    );
    await Future<void>.delayed(Duration.zero);
    expect(executor.maxConcurrentLaunches, 2);

    executor.releaseStart();
    final ids = await compoundFuture;
    expect(ids, hasLength(2));
    await mgr.dispose();
  });

  test('two sessions can run in parallel', () async {
    final executor = FakeRunExecutor(hangOnStart: true);
    final mgr = RunSessionManager(executor: executor, adapters: noopAdapter);
    final a = await mgr.start(ownedConfig(id: 'a'));
    final b = await mgr.start(ownedConfig(id: 'b'));
    expect(mgr.sessions, hasLength(2));
    expect(a.id, isNot(b.id));
    expect(mgr.hasRunning(a.selectionKey), isTrue);
    expect(mgr.hasRunning(b.selectionKey), isTrue);
    await mgr.dispose();
  });

  test('stop cancels running session', () async {
    final executor = FakeRunExecutor(hangOnStart: true);
    final mgr = RunSessionManager(executor: executor, adapters: noopAdapter);
    final s = await mgr.start(ownedConfig(id: 'a'));
    expect(s.status, RunSessionStatus.running);
    await mgr.stop(s.id);
    expect(mgr.session(s.id)?.status, RunSessionStatus.exited);
    expect(executor.stopCount, 1);
    await mgr.dispose();
  });

  test('natural exit updates status and exitCode', () async {
    final executor = FakeRunExecutor(exitCode: 42);
    final mgr = RunSessionManager(executor: executor, adapters: noopAdapter);
    final s = await mgr.start(ownedConfig(id: 'a'));
    await Future<void>.delayed(Duration.zero);
    expect(mgr.session(s.id)?.status, RunSessionStatus.exited);
    expect(mgr.session(s.id)?.exitCode, 42);
    expect(mgr.hasRunning(s.selectionKey), isFalse);
    await mgr.dispose();
  });

  test('restart stops then starts a new session', () async {
    final executor = FakeRunExecutor(hangOnStart: true);
    final mgr = RunSessionManager(executor: executor, adapters: noopAdapter);
    final s = await mgr.start(ownedConfig(id: 'a'));
    final restarted = await mgr.restart(s.id);
    expect(restarted.id, isNot(s.id));
    expect(restarted.status, RunSessionStatus.running);
    expect(executor.startedSessionIds, hasLength(2));
    await mgr.dispose();
  });

  test('restart passes preferTerminalEntryId for bound terminal session',
      () async {
    final executor = FakeRunExecutor(hangOnStart: true);
    final mgr = RunSessionManager(executor: executor, adapters: noopAdapter);
    final owned = OwnedLaunchConfiguration(
      owner: _folder,
      configuration: const LaunchConfiguration(
        id: 'a',
        name: 'a',
        type: 'shellScript',
        extras: {
          'execute': 'scriptText',
          'scriptText': 'echo hi',
          'executeInTerminal': true,
          'allowMultipleInstances': true,
        },
      ),
    );
    final s = await mgr.start(owned);
    mgr.registerTerminalSession(entryId: 'term-bound', sessionId: s.id);

    final restarted = await mgr.restart(s.id);
    expect(restarted.id, isNot(s.id));
    expect(executor.preferredTerminalEntryIds, [null, 'term-bound']);
    await mgr.dispose();
  });

  test('compound starts all same-file members; partial failure keeps successes', () async {
    final executor = FakeRunExecutor(
      hangOnStart: true,
      failStartForConfigIds: {'b'},
    );
    final mgr = RunSessionManager(executor: executor, adapters: noopAdapter);
    final compound = const LaunchCompound(
      id: 'all',
      name: 'All',
      configurationIds: ['a', 'b'],
    );
    final configs = [
      ownedConfig(id: 'a'),
      ownedConfig(id: 'b'),
    ];
    final ids = await mgr.startCompound(
      compound: compound,
      documentConfigs: configs,
    );
    expect(ids, hasLength(1));
    expect(
      mgr.sessions.where((s) => s.status == RunSessionStatus.running),
      hasLength(1),
    );
    expect(mgr.lastCompoundErrors, isNotEmpty);
    await mgr.dispose();
  });

  test('stopCompound stops all returned session ids', () async {
    final executor = FakeRunExecutor(hangOnStart: true);
    final mgr = RunSessionManager(executor: executor, adapters: noopAdapter);
    final compound = const LaunchCompound(
      id: 'all',
      name: 'All',
      configurationIds: ['a', 'b'],
    );
    final configs = [
      ownedConfig(id: 'a'),
      ownedConfig(id: 'b'),
    ];
    final ids = await mgr.startCompound(
      compound: compound,
      documentConfigs: configs,
    );
    await mgr.stopCompound(ids);
    for (final id in ids) {
      expect(mgr.session(id)?.status, RunSessionStatus.exited);
    }
    await mgr.dispose();
  });

  test('non-process type routes to adapter launcher', () async {
    final mgr = RunSessionManager(
      executor: FakeRunExecutor(),
      adapters: noopAdapter,
    );
    final flutter = OwnedLaunchConfiguration(
      owner: _folder,
      configuration: const LaunchConfiguration(
        id: 'main',
        name: 'main',
        type: 'flutter',
      ),
    );
    await expectLater(
      mgr.start(flutter),
      throwsA(
        isA<UnimplementedError>().having(
          (e) => e.message,
          'message',
          'Launch adapter: Task 6',
        ),
      ),
    );
    await mgr.dispose();
  });

  test('terminal-backed shellScript does not watch exit code', () async {
    final executor = FakeRunExecutor(exitCode: 0);
    final mgr = RunSessionManager(executor: executor, adapters: noopAdapter);
    final owned = OwnedLaunchConfiguration(
      owner: _folder,
      configuration: const LaunchConfiguration(
        id: 'a',
        name: 'a',
        type: 'shellScript',
        extras: {
          'execute': 'scriptText',
          'scriptText': 'echo hi',
          'executeInTerminal': true,
        },
      ),
    );
    final s = await mgr.start(owned);
    await Future<void>.delayed(Duration.zero);
    expect(mgr.session(s.id)?.status, RunSessionStatus.running);
    expect(mgr.session(s.id)?.exitCode, isNull);
    await mgr.stop(s.id);
    expect(mgr.session(s.id)?.status, RunSessionStatus.exited);
    await mgr.dispose();
  });

  test('non-terminal shellScript still watches exit code', () async {
    final executor = FakeRunExecutor(exitCode: 7);
    final mgr = RunSessionManager(executor: executor, adapters: noopAdapter);
    final owned = OwnedLaunchConfiguration(
      owner: _folder,
      configuration: const LaunchConfiguration(
        id: 'a',
        name: 'a',
        type: 'shellScript',
        extras: {
          'execute': 'scriptText',
          'scriptText': 'echo hi',
          'executeInTerminal': false,
        },
      ),
    );
    final s = await mgr.start(owned);
    await Future<void>.delayed(Duration.zero);
    expect(mgr.session(s.id)?.status, RunSessionStatus.exited);
    expect(mgr.session(s.id)?.exitCode, 7);
    await mgr.dispose();
  });

  test('markExitedForTerminalEntry exits bound session without interrupt', () async {
    final executor = FakeRunExecutor(hangOnStart: true);
    final mgr = RunSessionManager(executor: executor, adapters: noopAdapter);
    final owned = OwnedLaunchConfiguration(
      owner: _folder,
      configuration: const LaunchConfiguration(
        id: 'a',
        name: 'a',
        type: 'shellScript',
        extras: {
          'execute': 'scriptText',
          'scriptText': 'echo hi',
          'executeInTerminal': true,
        },
      ),
    );
    final s = await mgr.start(owned);
    expect(mgr.session(s.id)?.status, RunSessionStatus.running);

    mgr.registerTerminalSession(entryId: 'term-1', sessionId: s.id);
    mgr.markExitedForTerminalEntry('term-1');

    expect(mgr.session(s.id)?.status, RunSessionStatus.exited);
    expect(executor.stopCount, 0);

    // Unknown / already-cleared entry is a no-op.
    mgr.markExitedForTerminalEntry('term-1');
    expect(executor.stopCount, 0);
    await mgr.dispose();
  });
}
