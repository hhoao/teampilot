import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/services/app_storage.dart';

Directory? _testAppDataDir;

/// Initializes app paths for cubit tests that spawn team env.
void setUpTestAppStorage() {
  _testAppDataDir = Directory.systemTemp.createTempSync('test_app_data_');
  AppPathsBootstrapper.setCurrentForTesting(AppPaths(_testAppDataDir!.path));
}

void tearDownTestAppStorage() {
  AppPathsBootstrapper.resetForTesting();
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
