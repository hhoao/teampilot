import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/host/host_one_shot_runner.dart';
import 'package:teampilot/services/host/process_run_handle.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/run/process_run_executor.dart';
import 'package:teampilot/services/workspace/repo_clone_service.dart';

class _FakeHandle implements ProcessRunHandle {
  _FakeHandle(
    this.exit, {
    List<String> stderrLines = const [],
    List<String> stdoutLines = const [],
  }) : stderr = _linesStream(stderrLines),
       stdout = _linesStream(stdoutLines);

  static Stream<List<int>> _linesStream(List<String> lines) {
    final ctrl = StreamController<List<int>>();
    () async {
      for (final line in lines) {
        ctrl.add(line.codeUnits);
      }
      await ctrl.close();
    }();
    return ctrl.stream;
  }

  final int exit;

  @override
  Future<int> get exitCode => Future.value(exit);

  @override
  final Stream<List<int>> stdout;

  @override
  final Stream<List<int>> stderr;

  var killed = false;

  @override
  void kill() => killed = true;
}

/// Handle whose exit code only resolves when the test completes it — used to
/// observe mid-run cancellation deterministically.
class _ControllableHandle implements ProcessRunHandle {
  _ControllableHandle({List<String> stderrLines = const []})
    : stderr = _FakeHandle._linesStream(stderrLines);

  final _exit = Completer<int>();
  var killed = false;

  void completeExit(int code) => _exit.complete(code);

  @override
  Future<int> get exitCode => _exit.future;

  @override
  Stream<List<int>> get stdout => const Stream.empty();

  @override
  final Stream<List<int>> stderr;

  @override
  void kill() => killed = true;
}

class _RecordingSpawner {
  final calls = <({String executable, List<String> arguments})>[];
  ProcessRunHandle pendingHandle = _FakeHandle(0);
  Object? pendingError;

  ProcessSpawner get spawner =>
      ({
        required String executable,
        required List<String> arguments,
        required String workingDirectory,
        Map<String, String>? environment,
        bool runInShell = false,
        bool includeParentEnvironment = true,
      }) async {
        calls.add((executable: executable, arguments: arguments));
        final error = pendingError;
        if (error != null) throw error;
        return pendingHandle;
      };
}

class _FakeFs implements Filesystem {
  final files = <String>{};
  final dirs = <String>{};
  final deleted = <String>[];

  @override
  p.Context get pathContext => p.Context(style: p.Style.posix);

  @override
  Future<FsStat> stat(String path) async => FsStat(
    kind: dirs.contains(path)
        ? FsEntityKind.directory
        : files.contains(path)
        ? FsEntityKind.file
        : FsEntityKind.notFound,
  );

  @override
  Future<void> removeRecursive(String path) async {
    deleted.add(path);
    dirs.remove(path);
    files.remove(path);
  }

  @override
  Future<void> ensureDir(String path) async => dirs.add(path);

  @override
  Future<void> rename(String from, String to) async {
    throw UnimplementedError();
  }

  @override
  Future<String?> readString(String path) async {
    throw UnimplementedError();
  }

  @override
  Future<List<int>?> readBytes(String path) async {
    throw UnimplementedError();
  }

  @override
  Future<void> writeString(String path, String content) async {
    throw UnimplementedError();
  }

  @override
  Future<void> writeBytes(String path, List<int> bytes) async {
    throw UnimplementedError();
  }

  @override
  Future<List<int>?> readBytesRange(String path, int offset, int length) async {
    throw UnimplementedError();
  }

  @override
  Future<void> appendBytes(String path, List<int> bytes) async {
    throw UnimplementedError();
  }

  @override
  Future<void> atomicWrite(String path, String content) async {
    throw UnimplementedError();
  }

  @override
  Future<List<FsDirEntry>> listDir(String path) async {
    throw UnimplementedError();
  }

  @override
  Future<bool> createSymlink({
    required String target,
    required String linkPath,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<String?> readSymlinkTarget(String linkPath) async {
    throw UnimplementedError();
  }

  @override
  Future<String?> resolveSymlink(String path) async {
    throw UnimplementedError();
  }

  @override
  Future<void> copyTree({
    required String source,
    required String destination,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<void> copyFile(String source, String destination) async {
    throw UnimplementedError();
  }

  @override
  Future<List<FsDirEntry>> listDirRecursive(String path) async {
    throw UnimplementedError();
  }

  @override
  Future<String> createTempDir({String? prefix, String? parent}) async {
    throw UnimplementedError();
  }

  @override
  Future<void> appendString(String path, String content) async {
    throw UnimplementedError();
  }
}

class _FakeHostRunner implements RepoCloneHostRunner {
  _FakeHostRunner({this.gitExit = 0});

  final int gitExit;
  final fs = _FakeFs();

  @override
  Future<HostRunResult> checkGit(RepoCloneRequest request) async =>
      HostRunResult(
        exitCode: gitExit,
        stdout: 'git version 2.43.0',
        stderr: '',
      );

  @override
  Future<Filesystem> filesystemFor(String targetId) async => fs;
}

void main() {
  test('dirNameFromUrl strips .git and trailing slash', () {
    expect(repoCloneDirNameFromUrl('https://github.com/owner/repo.git'), 'repo');
    expect(repoCloneDirNameFromUrl('https://github.com/owner/repo/'), 'repo');
    expect(repoCloneDirNameFromUrl('git@host:owner/repo.git'), 'repo');
    expect(repoCloneDirNameFromUrl('ssh://git@host/owner/repo.git'), 'repo');
    expect(repoCloneDirNameFromUrl('git@host:repo.git'), 'repo');
    expect(repoCloneDirNameFromUrl('https://github.com/owner/.git'), '');
    expect(repoCloneDirNameFromUrl(''), '');
  });

  test('urlLooksValid accepts known schemes, rejects junk', () {
    expect(repoCloneUrlLooksValid('https://github.com/o/r.git'), isTrue);
    expect(repoCloneUrlLooksValid('git@github.com:o/r.git'), isTrue);
    expect(repoCloneUrlLooksValid('git://github.com/o/r.git'), isTrue);
    expect(repoCloneUrlLooksValid('ssh://git@host/o/r.git'), isTrue);
    expect(repoCloneUrlLooksValid('not a url'), isFalse);
    expect(repoCloneUrlLooksValid(''), isFalse);
    expect(repoCloneUrlLooksValid('   '), isFalse);
    expect(repoCloneUrlLooksValid('ftp://github.com/o/r.git'), isFalse);
  });

  test('parseFraction reads Receiving objects percent', () {
    expect(
      repoCloneParseFraction('Receiving objects:  45% (56/123), 3.2 MiB'),
      0.45,
    );
    expect(repoCloneParseFraction('Resolving deltas: 100% (12/12)'), 1.0);
    expect(repoCloneParseFraction('remote: Counting objects: 3, done.'), isNull);
  });

  test('clone builds git clone --progress with local plan and succeeds', () async {
    final spawner = _RecordingSpawner();
    final service = RepoCloneService(
      executor: ProcessRunExecutor(spawner: spawner.spawner),
      hostRunner: _FakeHostRunner(),
    );
    final result = await service.clone(
      RepoCloneRequest(
        url: 'https://github.com/o/r.git',
        targetId: 'local',
        parentDir: '/home/me/src',
        dirName: 'r',
      ),
      onProgress: (_) {},
      isCancelled: () => false,
    );
    expect(result.outcome, RepoCloneOutcome.succeeded);
    expect(result.destPath, '/home/me/src/r');
    expect(spawner.calls.single.executable, 'git');
    expect(
      spawner.calls.single.arguments,
      ['clone', '--progress', '--', 'https://github.com/o/r.git', 'r'],
    );
  });

  test('clone reports fraction and subtitle from stderr', () async {
    final spawner = _RecordingSpawner()
      ..pendingHandle = _FakeHandle(
        0,
        stderrLines: [
          'remote: Counting objects: 3, done.',
          'Receiving objects:  45% (56/123), 3.2 MiB | 1.1 MiB/s',
        ],
      );
    final progress = <RepoCloneProgress>[];
    final service = RepoCloneService(
      executor: ProcessRunExecutor(spawner: spawner.spawner),
      hostRunner: _FakeHostRunner(),
    );
    await service.clone(
      RepoCloneRequest(
        url: 'https://github.com/o/r.git',
        targetId: 'local',
        parentDir: '/src',
        dirName: 'r',
      ),
      onProgress: progress.add,
      isCancelled: () => false,
    );
    expect(progress.any((p) => p.fraction == 0.45), isTrue);
    expect(progress.any((p) => p.subtitle?.contains('Receiving') ?? false), isTrue);
  });

  test('clone fails when destination exists', () async {
    final host = _FakeHostRunner()..fs.dirs.add('/src/r');
    final spawner = _RecordingSpawner();
    final service = RepoCloneService(
      executor: ProcessRunExecutor(spawner: spawner.spawner),
      hostRunner: host,
    );
    final result = await service.clone(
      RepoCloneRequest(
        url: 'https://github.com/o/r.git',
        targetId: 'local',
        parentDir: '/src',
        dirName: 'r',
      ),
      onProgress: (_) {},
      isCancelled: () => false,
    );
    expect(result.outcome, RepoCloneOutcome.failed);
    expect(result.errorDetail, 'dest-exists');
    expect(result.destPath, '/src/r');
    expect(spawner.calls, isEmpty);
  });

  test('clone fails fast when git is missing on target', () async {
    final spawner = _RecordingSpawner();
    final service = RepoCloneService(
      executor: ProcessRunExecutor(spawner: spawner.spawner),
      hostRunner: _FakeHostRunner(gitExit: 127),
    );
    final result = await service.clone(
      RepoCloneRequest(
        url: 'https://github.com/o/r.git',
        targetId: 'local',
        parentDir: '/src',
        dirName: 'r',
      ),
      onProgress: (_) {},
      isCancelled: () => false,
    );
    expect(result.outcome, RepoCloneOutcome.failed);
    expect(result.errorDetail, 'git-missing');
    expect(spawner.calls, isEmpty);
  });

  test('clone failure carries stderr tail', () async {
    final spawner = _RecordingSpawner()
      ..pendingHandle = _FakeHandle(
        128,
        stderrLines: ['fatal: could not read Username for https://github.com'],
      );
    final service = RepoCloneService(
      executor: ProcessRunExecutor(spawner: spawner.spawner),
      hostRunner: _FakeHostRunner(),
    );
    final result = await service.clone(
      RepoCloneRequest(
        url: 'https://github.com/o/r.git',
        targetId: 'local',
        parentDir: '/src',
        dirName: 'r',
      ),
      onProgress: (_) {},
      isCancelled: () => false,
    );
    expect(result.outcome, RepoCloneOutcome.failed);
    expect(result.errorDetail, contains('could not read Username'));
  });

  test('cancelled clone kills the process and returns cancelled', () async {
    final handle = _ControllableHandle(
      stderrLines: ['Receiving objects:   5% (1/20)'],
    );
    final spawner = _RecordingSpawner()..pendingHandle = handle;
    final host = _FakeHostRunner();
    final service = RepoCloneService(
      executor: ProcessRunExecutor(spawner: spawner.spawner),
      hostRunner: host,
    );
    var cancelled = false;
    final cloneFuture = service.clone(
      RepoCloneRequest(
        url: 'https://github.com/o/r.git',
        targetId: 'local',
        parentDir: '/src',
        dirName: 'r',
      ),
      // First progress line means git is running and has created the dir.
      onProgress: (_) {
        host.fs.dirs.add('/src/r');
        cancelled = true;
      },
      isCancelled: () => cancelled,
    );
    // The first stderr event flips the cancellation flag; the service's
    // macrotask pump then observes it and kills the process. Poll turns of
    // the event loop until the kill lands (the service's internal pump timer
    // may be queued after this test's own timers).
    while (!handle.killed) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(handle.killed, isTrue);
    handle.completeExit(130);
    final result = await cloneFuture;
    expect(result.outcome, RepoCloneOutcome.cancelled);
    // Cancelled cleanup is awaited and removes the partial clone.
    expect(host.fs.deleted, ['/src/r']);
  });

  test('clone failure with already-exists stderr never deletes destination',
      () async {
    // Race: pre-check stat said absent, but git finds a non-empty directory
    // and fails — the pre-existing directory must survive.
    final spawner = _RecordingSpawner()
      ..pendingHandle = _FakeHandle(
        128,
        stderrLines: [
          "fatal: destination path 'r' already exists and is not an empty "
          'directory.',
        ],
      );
    final host = _FakeHostRunner();
    final service = RepoCloneService(
      executor: ProcessRunExecutor(spawner: spawner.spawner),
      hostRunner: host,
    );
    final result = await service.clone(
      RepoCloneRequest(
        url: 'https://github.com/o/r.git',
        targetId: 'local',
        parentDir: '/src',
        dirName: 'r',
      ),
      // The raced directory exists by the time git reports the failure.
      onProgress: (_) => host.fs.dirs.add('/src/r'),
      isCancelled: () => false,
    );
    expect(result.outcome, RepoCloneOutcome.failed);
    expect(result.errorDetail, contains('already exists'));
    expect(host.fs.deleted, isEmpty);
  });

  test('clone failure skips cleanup when pre-check stat threw', () async {
    // stat errors on the pre-check (permissions / transport hiccup):
    // absence unproven, so a failure must not risk deleting anything.
    final host = _StatThrowsHostRunner();
    final spawner = _RecordingSpawner()
      ..pendingHandle = _FakeHandle(128, stderrLines: ['fatal: bad repo']);
    final service = RepoCloneService(
      executor: ProcessRunExecutor(spawner: spawner.spawner),
      hostRunner: host,
    );
    final result = await service.clone(
      RepoCloneRequest(
        url: 'https://github.com/o/r.git',
        targetId: 'local',
        parentDir: '/src',
        dirName: 'r',
      ),
      onProgress: (_) {},
      isCancelled: () => false,
    );
    expect(result.outcome, RepoCloneOutcome.failed);
    expect(result.errorDetail, contains('fatal: bad repo'));
    expect(host.fs.deleted, isEmpty);
  });

  test('spawn StateError surfaces as failed outcome, not an exception', () async {
    final spawner = _RecordingSpawner()
      ..pendingError = StateError('SSH process execution is not configured');
    final service = RepoCloneService(
      executor: ProcessRunExecutor(spawner: spawner.spawner),
      hostRunner: _FakeHostRunner(),
    );
    final result = await service.clone(
      RepoCloneRequest(
        url: 'https://github.com/o/r.git',
        targetId: 'local',
        parentDir: '/src',
        dirName: 'r',
      ),
      onProgress: (_) {},
      isCancelled: () => false,
    );
    expect(result.outcome, RepoCloneOutcome.failed);
    expect(
      result.errorDetail,
      contains('SSH process execution is not configured'),
    );
  });

  test('stdout lines do not produce progress or fractions', () async {
    // A percent line on stdout (never a git --progress stream) must not be
    // parsed as progress; the stderr line must be.
    final spawner = _RecordingSpawner()
      ..pendingHandle = _FakeHandle(
        0,
        stdoutLines: ['Receiving objects:  99% (999/999), 9 MiB'],
        stderrLines: ['Receiving objects:  45% (56/123), 3.2 MiB'],
      );
    final progress = <RepoCloneProgress>[];
    final service = RepoCloneService(
      executor: ProcessRunExecutor(spawner: spawner.spawner),
      hostRunner: _FakeHostRunner(),
    );
    await service.clone(
      RepoCloneRequest(
        url: 'https://github.com/o/r.git',
        targetId: 'local',
        parentDir: '/src',
        dirName: 'r',
      ),
      onProgress: progress.add,
      isCancelled: () => false,
    );
    expect(progress.where((p) => p.fraction == 0.99), isEmpty);
    expect(progress.where((p) => p.subtitle?.contains('99%') ?? false),
        isEmpty);
    expect(progress.where((p) => p.fraction == 0.45), isNotEmpty);
  });

  test('clone cancelled after success exit reports succeeded and keeps dir',
      () async {
    // Cancellation is observed only after git already exited 0 — the clone
    // completed and must not be reported cancelled or deleted.
    final handle = _ControllableHandle();
    final spawner = _RecordingSpawner()..pendingHandle = handle;
    final host = _FakeHostRunner();
    final service = RepoCloneService(
      executor: ProcessRunExecutor(spawner: spawner.spawner),
      hostRunner: host,
    );
    var cancelled = false;
    final cloneFuture = service.clone(
      RepoCloneRequest(
        url: 'https://github.com/o/r.git',
        targetId: 'local',
        parentDir: '/src',
        dirName: 'r',
      ),
      onProgress: (_) => host.fs.dirs.add('/src/r'),
      isCancelled: () => cancelled,
    );
    await Future<void>.delayed(Duration.zero);
    handle.completeExit(0);
    cancelled = true; // Flips after exit 0, before the result is judged.
    final result = await cloneFuture;
    expect(result.outcome, RepoCloneOutcome.succeeded);
    expect(host.fs.deleted, isEmpty);
  });
}

/// Host runner whose stat() throws — simulates transport/permission errors
/// during the destination pre-check.
class _StatThrowsHostRunner implements RepoCloneHostRunner {
  final fs = _StatThrowsFs();

  @override
  Future<HostRunResult> checkGit(RepoCloneRequest request) async =>
      HostRunResult(exitCode: 0, stdout: 'git version 2.43.0', stderr: '');

  @override
  Future<Filesystem> filesystemFor(String targetId) async => fs;
}

class _StatThrowsFs extends _FakeFs {
  @override
  Future<FsStat> stat(String path) async => throw Exception('stat failed');
}
