import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/services/git/git_service.dart';
import 'package:teampilot/services/git/git_worktree_service.dart';
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
    runner: (executable, arguments, {stdoutEncoding, stderrEncoding}) async =>
        ProcessResult(0, 1, '', ''),
  );
  // The worktree sidebar self-builds a GitWorktreeService that would otherwise
  // spawn `git` when a workspace mounts. Use a process-free runner so it
  // reports "no worktrees" instead of leaking subprocesses in widget tests.
  GitWorktreeService.debugOverrideFactory = () => GitWorktreeService(
    runner: (executable, arguments, {stdoutEncoding, stderrEncoding}) async =>
        ProcessResult(0, 1, '', ''),
  );
  WorkspaceFsWatcher.debugDisable = true;
}

void tearDownTestAppStorage() {
  GitService.debugOverrideFactory = null;
  GitWorktreeService.debugOverrideFactory = null;
  WorkspaceFsWatcher.debugDisable = false;
  AppStorage.resetForTesting();
  AppPathsBootstrapper.resetForTesting();
  DefaultWorkspaceDirectory.resetForTesting();
  final dir = _testAppDataDir;
  _testAppDataDir = null;
  if (dir != null && dir.existsSync()) {
    dir.deleteSync(recursive: true);
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
