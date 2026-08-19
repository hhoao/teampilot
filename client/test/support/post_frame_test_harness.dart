import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/cubits/automation_cubit.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/skill_cubit.dart';
import 'package:teampilot/repositories/automation_repository.dart';
import 'package:teampilot/repositories/launch_profile_repository.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/repositories/skill_repository.dart';
import 'package:teampilot/services/automation/automation_bus_gateway.dart';
import 'package:teampilot/services/automation/automation_dispatcher.dart';
import 'package:teampilot/services/automation/automation_schedule_calculator.dart';
import 'package:teampilot/services/automation/automation_scheduler.dart';
import 'package:teampilot/services/git/git_command_runner.dart';
import 'package:teampilot/services/git/git_service.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/io/workspace_fs_watcher.dart';
import 'package:teampilot/services/resource_manager/process_metrics_service.dart';
import 'package:teampilot/services/resource_manager/resource_memory_models.dart';
import 'package:teampilot/services/skill/registry/skill_registry_config_service.dart';
import 'package:teampilot/services/skill/registry/skill_registry_source.dart';
import 'package:teampilot/services/skill/skill_acquisition_engine.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/storage/workspace_layout.dart';

Directory? _testAppDataDir;

/// Instant empty snapshot — avoids host `ps`/`powershell` and pending timers.
class _TestProcessMetricsService extends ProcessMetricsService {
  @override
  Future<ResourceMemorySnapshot> collect({
    required Map<String, int> registeredPids,
    required Map<String, String> bindingKeyToGroupKey,
  }) async {
    return ResourceMemorySnapshot(collectedAt: DateTime.now());
  }
}

/// Initializes app paths and [RuntimeStorageContext] for cubit tests.
void setUpTestAppStorage() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _testAppDataDir = Directory.systemTemp.createTempSync('test_app_data_');
  final paths = AppPaths(_testAppDataDir!.path);
  AppStorage.installForTesting(
    filesystem: LocalFilesystem(
      pathContext: AppPaths.pathContextForDataRoot(paths.basePath),
    ),
    paths: paths,
    home: _testAppDataDir!.path,
    cwd: _testAppDataDir!.path,
  );
  // The source control panel self-builds a GitService that would otherwise
  // spawn a real `git` process on mount, leaking timers in widget tests. Use a
  // process-free runner so it reports "git unavailable" instead.
  GitService.debugOverrideFactory = () => GitService(
    runner: LocalGitCommandRunner(
      runner: (executable, arguments, {stdoutEncoding, stderrEncoding}) async =>
          ProcessResult(0, 1, '', ''),
    ),
  );
  // Status-bar Resource Manager starts a host process sweep on mount; under
  // fake_async that leaves a 5s `.timeout` timer pending after dispose.
  ProcessMetricsService.debugOverrideFactory = _TestProcessMetricsService.new;
  WorkspaceFsWatcher.debugDisable = true;
}

/// Isolated [LaunchProfileRepository] for tests.
///
/// The index snapshot is stored beside [launchProfilesDir], so the repo root must
/// not be a bare system-temp leaf (that would share `/tmp/launch-profiles-index.json`).
LaunchProfileRepository testLaunchProfileRepository(Directory isolatedRoot) {
  final profilesDir = Directory(p.join(isolatedRoot.path, 'launch-profiles'));
  if (!profilesDir.existsSync()) {
    profilesDir.createSync(recursive: true);
  }
  return LaunchProfileRepository(rootDir: profilesDir.path);
}

void tearDownTestAppStorage() {
  GitService.debugOverrideFactory = null;
  ProcessMetricsService.debugOverrideFactory = null;
  WorkspaceFsWatcher.debugDisable = false;
  AppStorage.resetForTesting();
  AppPathsBootstrapper.resetForTesting();
  DefaultWorkspaceDirectory.resetForTesting();
  final dir = _testAppDataDir;
  _testAppDataDir = null;
  if (dir != null && dir.existsSync()) {
    unawaited(deleteTempDirBestEffort(dir));
  }
}

/// Default [SkillCubit] for tests that need the provider registered but do not
/// exercise skill actions (empty registry config, no sources).
SkillCubit testSkillCubit({SkillAcquisitionEngine? acquisitionEngine}) =>
    SkillCubit(
      SkillRepository(),
      registryConfigService: SkillRegistryConfigService(),
      initialSources: const <SkillRegistrySource>[],
      rebuildSources: (config) => const <SkillRegistrySource>[],
      acquisitionEngine: acquisitionEngine,
    );

/// Runs a post-frame callback and awaits async continuations (e.g. spawn env).
///
/// [ChatCubit] schedules `() async { ... }` bodies as [VoidCallback]s; invoking
/// them through [dynamic] captures the returned [Future].
Future<void> runScheduledCallback(VoidCallback callback) async {
  final dynamic result = (callback as dynamic Function())();
  if (result is Future) {
    await result;
  }
  await pumpEventQueue();
}

/// Queues [ChatCubit] post-frame work for deterministic draining in tests.
class PostFrameTestHarness {
  final _queue = <VoidCallback>[];

  PostFrameScheduler get scheduler => _queue.add;

  bool get hasPendingCallbacks => _queue.isNotEmpty;

  Future<void> flush() async {
    while (_queue.isNotEmpty) {
      await runScheduledCallback(_queue.removeAt(0));
    }
  }
}

/// Drains post-frame work when using an explicit callback queue.
Future<void> drainPostFrameQueue(List<VoidCallback> queue) async {
  while (queue.isNotEmpty) {
    await runScheduledCallback(queue.removeAt(0));
  }
}

/// Drains microtasks after tests (e.g. [ChatCubit] `unawaited` session persist).
Future<void> drainPendingAsyncWork({int rounds = 5}) async {
  for (var i = 0; i < rounds; i++) {
    await pumpEventQueue();
    await Future<void>.delayed(Duration.zero);
  }
}

/// Polls [predicate] until true or [timeout] (for unawaited cubit side effects).
Future<void> waitUntil(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 5),
  Duration step = const Duration(milliseconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate() && DateTime.now().isBefore(deadline)) {
    await pumpEventQueue();
    await Future<void>.delayed(step);
  }
}

/// Pumps frames until [predicate] is true, with a fake-async-safe deadline.
///
/// Unlike [WidgetTester.pumpAndSettle], this cannot wait indefinitely when a
/// widget keeps an animation, timer, or stream alive. The elapsed duration is
/// accumulated from the requested pump steps so the deadline remains
/// deterministic under Flutter test's fake clock.
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() predicate, {
  String description = 'widget condition',
  Duration timeout = const Duration(seconds: 2),
  Duration step = const Duration(milliseconds: 16),
}) async {
  if (timeout < Duration.zero) {
    throw ArgumentError.value(timeout, 'timeout', 'must not be negative');
  }
  if (step <= Duration.zero) {
    throw ArgumentError.value(step, 'step', 'must be positive');
  }

  var elapsed = Duration.zero;
  while (!predicate()) {
    if (elapsed >= timeout) {
      throw TestFailure('Timed out waiting for $description');
    }
    await tester.pump(step);
    elapsed += step;
  }
}

/// Best-effort temp dir cleanup (Windows CI may still hold profile files briefly).
Future<void> deleteTempDirBestEffort(Directory dir) async {
  for (var attempt = 0; attempt < 12; attempt++) {
    try {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
      return;
    } on FileSystemException {
      await drainPendingAsyncWork(rounds: 2);
      await Future<void>.delayed(Duration(milliseconds: 30 * (attempt + 1)));
    }
  }
}

AutomationRepository testAutomationRepository() {
  if (_testAppDataDir != null) {
    return AutomationRepository(
      fs: AppStorage.fs,
      layout: WorkspaceLayout(teampilotRoot: AppStorage.paths.basePath),
    );
  }
  return AutomationRepository(
    fs: LocalFilesystem(),
    layout: WorkspaceLayout(teampilotRoot: '/tmp/teampilot-test-automation'),
  );
}

class _NoopAutomationBusGateway implements AutomationBusGateway {
  @override
  Future<void> deliverUserCommandToMember(
    String sessionId,
    String memberId,
    String message,
  ) async {}

  @override
  Future<void> ensureMemberReady(String sessionId, String memberId) async {}
}

AutomationCubit testAutomationCubit({SessionRepository? sessionRepository}) {
  return testAutomationSetup(sessionRepository: sessionRepository).cubit;
}

({AutomationCubit cubit, AutomationRepository repo}) testAutomationSetup({
  SessionRepository? sessionRepository,
}) {
  final repo = testAutomationRepository();
  final calc = AutomationScheduleCalculator();
  final sessions = sessionRepository ?? SessionRepository();
  final dispatcher = AutomationDispatcher(
    repository: repo,
    scheduleCalculator: calc,
    sessionRepository: sessions,
    busGateway: _NoopAutomationBusGateway(),
    requestOpenSession: (_) async => SessionOpenStatus.opened,
    requestCreateAndOpenSession: (_) async => SessionOpenStatus.opened,
    workspaceById: (_) => null,
    teamById: (_) => null,
  );
  final scheduler = AutomationScheduler(
    repository: repo,
    dispatcher: dispatcher,
    scheduleCalculator: calc,
  );
  final cubit = AutomationCubit(
    repository: repo,
    scheduler: scheduler,
    scheduleCalculator: calc,
  );
  return (cubit: cubit, repo: repo);
}

/// Minimal [ChatCubit] for tests — injects [testAutomationRepository] by default.
ChatCubit testChatCubit({
  required String Function() executableResolver,
  AutomationRepository? automationRepository,
  SessionRepository? sessionRepository,
}) {
  return ChatCubit(
    executableResolver: executableResolver,
    automationRepository: automationRepository ?? testAutomationRepository(),
    sessionRepository: sessionRepository,
  );
}

/// Drains post-frame work and closes [cubit] so session persist timers settle.
Future<void> tearDownChatCubitWithSessionPersist(
  ChatCubit cubit,
  PostFrameTestHarness postFrame,
) async {
  await postFrame.flush();
  await drainPendingAsyncWork(rounds: 15);
  if (!cubit.isClosed) {
    await cubit.close();
  }
  await drainPendingAsyncWork(rounds: 15);
}
