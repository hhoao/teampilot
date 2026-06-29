import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/repositories/launch_profile_repository.dart';
import 'package:teampilot/services/git/git_command_runner.dart';
import 'package:teampilot/services/git/git_service.dart';
import 'package:teampilot/services/io/workspace_fs_watcher.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/io/local_filesystem.dart';

Directory? _testAppDataDir;

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
  WorkspaceFsWatcher.debugDisable = false;
  AppStorage.resetForTesting();
  AppPathsBootstrapper.resetForTesting();
  DefaultWorkspaceDirectory.resetForTesting();
  final dir = _testAppDataDir;
  _testAppDataDir = null;
  if (dir != null && dir.existsSync()) {
    _deleteTestDirWithRetry(dir);
  }
}

void _deleteTestDirWithRetry(Directory dir, {int attempts = 8}) {
  for (var i = 0; i < attempts; i++) {
    try {
      dir.deleteSync(recursive: true);
      return;
    } on FileSystemException {
      if (i == attempts - 1) rethrow;
      sleep(const Duration(milliseconds: 250));
    }
  }
}

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
