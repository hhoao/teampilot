import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/io/workspace_fs_watcher.dart';

import '../../support/in_memory_filesystem.dart';

/// In-memory filesystem that can also push change events, used to drive
/// [WorkspaceFsWatcher] without touching the real disk.
///
/// [watchStream] is the stream of the current watch; [killStream] simulates
/// the Dart SDK killing a native Windows watch ("Directory watcher closed
/// unexpectedly" — the SDK closes the stream instead of erroring). A
/// subsequent [watchTree] hands out a fresh stream, like the SDK would when
/// re-opening the watch handle.
class _WatchableFs extends InMemoryFilesystem implements FsWatcher {
  StreamController<FsChangeEvent>? _controller =
      StreamController<FsChangeEvent>.broadcast();
  var closeCount = 0;
  var watchCount = 0;

  void emit(FsChangeType type, String path) => _controller?.add(
    FsChangeEvent(path: path, type: type),
  );

  Stream<FsChangeEvent> get watchStream => _controller!.stream;

  /// Simulates the SDK killing the native watch: closes the event stream
  /// (onDone for the watcher's subscription).
  Future<void> killStream() {
    final controller = _controller!;
    _controller = null;
    return controller.close();
  }

  /// Simulates the SDK's "Directory watcher failed due to: ..." failure mode.
  void addStreamError() =>
      _controller!.addError(const FileSystemException('watch failed'));

  @override
  FsTreeWatch watchTree(String path) {
    watchCount++;
    _controller ??= StreamController<FsChangeEvent>.broadcast();
    final controller = _controller!;
    return FsTreeWatch(
      events: controller.stream,
      close: () async {
        closeCount++;
      },
    );
  }
}

void main() {
  group('WorkspaceFsWatcher', () {
    test('is unsupported and silent on a non-watching filesystem', () async {
      final watcher = WorkspaceFsWatcher(
        fs: InMemoryFilesystem(),
        root: '/repo',
      );
      addTearDown(watcher.dispose);

      expect(watcher.isSupported, isFalse);

      var fired = false;
      watcher.onChanged.listen((_) => fired = true);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(fired, isFalse);
    });

    test('poke() drives refresh even without a native watch', () async {
      // Mirrors the SSH/Android case: no FsWatcher, so disk events never fire,
      // but a turn-end activity poke still triggers a (debounced) refresh.
      final watcher = WorkspaceFsWatcher(
        fs: InMemoryFilesystem(),
        root: '/repo',
        debounce: const Duration(milliseconds: 20),
      );
      addTearDown(watcher.dispose);

      expect(watcher.isSupported, isFalse);

      var count = 0;
      watcher.onChanged.listen((_) => count++);

      watcher.poke();
      watcher.poke();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(count, 1);
    });

    test('poke() is a no-op after dispose', () async {
      final watcher = WorkspaceFsWatcher(
        fs: InMemoryFilesystem(),
        root: '/repo',
        debounce: const Duration(milliseconds: 20),
      );
      var count = 0;
      watcher.onChanged.listen((_) => count++);
      watcher.dispose();

      watcher.poke();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(count, 0);
    });

    test('collapses a burst of events into one debounced signal', () async {
      final fs = _WatchableFs();
      final watcher = WorkspaceFsWatcher(
        fs: fs,
        root: '/repo',
        debounce: const Duration(milliseconds: 20),
        autoStart: true,
      );
      addTearDown(watcher.dispose);

      expect(watcher.isSupported, isTrue);

      var count = 0;
      watcher.onChanged.listen((_) => count++);

      fs.emit(FsChangeType.created, '/repo/a.txt');
      fs.emit(FsChangeType.modified, '/repo/a.txt');
      fs.emit(FsChangeType.created, '/repo/b.txt');

      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(count, 1);

      // A later, separate burst yields another signal.
      fs.emit(FsChangeType.deleted, '/repo/a.txt');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(count, 2);
    });

    test('batches changed parent directories into the payload', () async {
      final fs = _WatchableFs();
      final watcher = WorkspaceFsWatcher(
        fs: fs,
        root: '/repo',
        debounce: const Duration(milliseconds: 20),
        autoStart: true,
      );
      addTearDown(watcher.dispose);

      final batches = <FsChangeBatch>[];
      watcher.onChanged.listen(batches.add);

      fs.emit(FsChangeType.created, '/repo/a.txt');
      fs.emit(FsChangeType.created, '/repo/sub/b.txt');
      fs.emit(FsChangeType.modified, '/repo/sub/c.txt');

      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(batches, hasLength(1));
      expect(batches.single.changedDirs, {'/repo', '/repo/sub'});
      expect(batches.single.structural, isTrue);
    });

    test('pure modified batches are marked non-structural', () async {
      // 文件内容写入不可能改变目录列表（FsDirEntry 只有 name+isDirectory），
      // 文件树消费方据此跳过整个批次。
      final fs = _WatchableFs();
      final watcher = WorkspaceFsWatcher(
        fs: fs,
        root: '/repo',
        debounce: const Duration(milliseconds: 20),
        autoStart: true,
      );
      addTearDown(watcher.dispose);

      final batches = <FsChangeBatch>[];
      watcher.onChanged.listen(batches.add);

      fs.emit(FsChangeType.modified, '/repo/a.txt');
      fs.emit(FsChangeType.modified, '/repo/sub/b.dart');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(batches.single.structural, isFalse);
      expect(batches.single.changedDirs, {'/repo', '/repo/sub'});
    });

    test('mixed batches are marked structural', () async {
      final fs = _WatchableFs();
      final watcher = WorkspaceFsWatcher(
        fs: fs,
        root: '/repo',
        debounce: const Duration(milliseconds: 20),
        autoStart: true,
      );
      addTearDown(watcher.dispose);

      final batches = <FsChangeBatch>[];
      watcher.onChanged.listen(batches.add);

      fs.emit(FsChangeType.modified, '/repo/a.txt');
      fs.emit(FsChangeType.created, '/repo/b.txt');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(batches.single.structural, isTrue);
    });

    test('poke() emits an empty set meaning full refresh', () async {
      final fs = _WatchableFs();
      final watcher = WorkspaceFsWatcher(
        fs: fs,
        root: '/repo',
        debounce: const Duration(milliseconds: 20),
      );
      addTearDown(watcher.dispose);

      final batches = <FsChangeBatch>[];
      watcher.onChanged.listen(batches.add);

      watcher.poke();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(batches, hasLength(1));
      expect(batches.single.changedDirs, isEmpty);
      expect(batches.single.structural, isTrue,
          reason: 'poke 语义未知 → 视为结构变更（消费方全量刷新）');
    });

    test('ignores churn inside noisy directories', () async {
      final fs = _WatchableFs();
      final watcher = WorkspaceFsWatcher(
        fs: fs,
        root: '/repo',
        debounce: const Duration(milliseconds: 20),
        autoStart: true,
      );
      addTearDown(watcher.dispose);

      final batches = <FsChangeBatch>[];
      watcher.onChanged.listen(batches.add);

      fs.emit(FsChangeType.created, '/repo/node_modules/x/index.js');
      fs.emit(FsChangeType.modified, '/repo/.dart_tool/package_config.json');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(batches, isEmpty);

      // A real source change still comes through.
      fs.emit(FsChangeType.created, '/repo/lib/main.dart');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(batches, hasLength(1));
      expect(batches.single.changedDirs, {'/repo/lib'});
      expect(batches.single.structural, isTrue);
    });

    test('stops emitting after dispose', () async {
      final fs = _WatchableFs();
      final watcher = WorkspaceFsWatcher(
        fs: fs,
        root: '/repo',
        debounce: const Duration(milliseconds: 20),
        autoStart: true,
      );

      var count = 0;
      watcher.onChanged.listen((_) => count++);
      fs.emit(FsChangeType.created, '/repo/a.txt');
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(count, 1);

      await watcher.stopAndDispose();

      fs.emit(FsChangeType.created, '/repo/a.txt');
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(count, 1);
    });

    test('suspend stops events and resume delivers again', () async {
      final fs = _WatchableFs();
      final watcher = WorkspaceFsWatcher(
        fs: fs,
        root: '/repo',
        debounce: const Duration(milliseconds: 20),
        autoStart: true,
      );
      addTearDown(watcher.dispose);

      var count = 0;
      watcher.onChanged.listen((_) => count++);

      fs.emit(FsChangeType.created, '/repo/a.txt');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(count, 1);

      watcher.suspend();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(fs.closeCount, 1);

      fs.emit(FsChangeType.created, '/repo/b.txt');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(count, 1);

      watcher.resume();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      fs.emit(FsChangeType.created, '/repo/c.txt');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(count, 2);
    });

    test('dispose closes the native tree watch', () async {
      final fs = _WatchableFs();
      final watcher = WorkspaceFsWatcher(
        fs: fs,
        root: '/repo',
        debounce: const Duration(milliseconds: 20),
        autoStart: true,
      );

      watcher.onChanged.listen((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(fs.closeCount, 0);

      await watcher.stopAndDispose();
      expect(fs.closeCount, 1);
    });

    test('native watch stays off until resume', () async {
      final fs = _WatchableFs();
      final watcher = WorkspaceFsWatcher(
        fs: fs,
        root: '/repo',
        debounce: const Duration(milliseconds: 20),
      );
      addTearDown(watcher.dispose);

      var count = 0;
      watcher.onChanged.listen((_) => count++);

      fs.emit(FsChangeType.created, '/repo/a.txt');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(count, 0);

      watcher.resume();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      fs.emit(FsChangeType.created, '/repo/b.txt');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(count, 1);
    });

    group('native watch self-healing', () {
      test('re-attaches the native watch after the stream closes', () async {
        // Windows SDK watch termination arrives as onDone, not onError
        // ("Directory watcher closed unexpectedly"): without re-attach the
        // watcher silently dies and the workspace never refreshes again.
        final fs = _WatchableFs();
        await fs.ensureDir('/repo');
        final watcher = WorkspaceFsWatcher(
          fs: fs,
          root: '/repo',
          debounce: const Duration(milliseconds: 20),
          autoStart: true,
          retryDelay: const Duration(milliseconds: 10),
        );
        addTearDown(watcher.dispose);

        final batches = <FsChangeBatch>[];
        watcher.onChanged.listen(batches.add);

        fs.emit(FsChangeType.created, '/repo/a.txt');
        await Future<void>.delayed(const Duration(milliseconds: 60));
        expect(batches, hasLength(1));

        // The SDK kills the watch. Events on the same stream must still
        // reach the re-attached subscription.
        await fs.killStream();
        await Future<void>.delayed(const Duration(milliseconds: 100));

        expect(fs.watchCount, 2, reason: 'watcher 应在流关闭后重新挂载原生 watch');

        fs.emit(FsChangeType.created, '/repo/b.txt');
        await Future<void>.delayed(const Duration(milliseconds: 60));
        expect(batches, hasLength(2));
      });

      test('re-attaches the native watch after a stream error', () async {
        final fs = _WatchableFs();
        await fs.ensureDir('/repo');
        final watcher = WorkspaceFsWatcher(
          fs: fs,
          root: '/repo',
          debounce: const Duration(milliseconds: 20),
          autoStart: true,
          retryDelay: const Duration(milliseconds: 10),
        );
        addTearDown(watcher.dispose);

        final batches = <FsChangeBatch>[];
        watcher.onChanged.listen(batches.add);

        // The other SDK failure mode: onError (e.g. "Directory watcher
        // failed due to: ..."). Emit an error on the stream the watcher
        // subscribed to; cancelOnError: false keeps it alive, but the
        // watcher should still re-attach.
        fs.addStreamError();
        await Future<void>.delayed(const Duration(milliseconds: 100));

        expect(fs.watchCount, 2);
      });

      test('does not re-attach after dispose', () async {
        final fs = _WatchableFs();
        await fs.ensureDir('/repo');
        final watcher = WorkspaceFsWatcher(
          fs: fs,
          root: '/repo',
          debounce: const Duration(milliseconds: 20),
          autoStart: true,
          retryDelay: const Duration(milliseconds: 10),
        );

        await watcher.stopAndDispose();
        expect(fs.watchCount, 1);

        await fs.killStream();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(fs.watchCount, 1);
      });

      test('does not re-attach while suspended', () async {
        final fs = _WatchableFs();
        await fs.ensureDir('/repo');
        final watcher = WorkspaceFsWatcher(
          fs: fs,
          root: '/repo',
          debounce: const Duration(milliseconds: 20),
          autoStart: true,
          retryDelay: const Duration(milliseconds: 10),
        );
        addTearDown(watcher.dispose);

        watcher.suspend();
        await Future<void>.delayed(const Duration(milliseconds: 20));

        await fs.killStream();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(fs.watchCount, 1, reason: 'suspend 期间不应自动重挂');
      });

      test('re-attach waits for the root directory to exist', () async {
        final fs = _WatchableFs();
        final watcher = WorkspaceFsWatcher(
          fs: fs,
          root: '/repo',
          debounce: const Duration(milliseconds: 20),
          autoStart: true,
          retryDelay: const Duration(milliseconds: 10),
        );
        addTearDown(watcher.dispose);

        final batches = <FsChangeBatch>[];
        watcher.onChanged.listen(batches.add);

        await fs.killStream();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(fs.watchCount, 1, reason: '根目录不存在时不应挂载 watch');

        await fs.ensureDir('/repo');
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(fs.watchCount, 2, reason: '根目录出现后应挂载 watch');

        fs.emit(FsChangeType.created, '/repo/b.txt');
        await Future<void>.delayed(const Duration(milliseconds: 60));
        expect(batches, hasLength(1));
      });
    });
  });
}
