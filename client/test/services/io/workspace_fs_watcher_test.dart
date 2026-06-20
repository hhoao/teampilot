import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/io/workspace_fs_watcher.dart';

import '../../support/in_memory_filesystem.dart';

/// In-memory filesystem that can also push change events, used to drive
/// [WorkspaceFsWatcher] without touching the real disk.
class _WatchableFs extends InMemoryFilesystem implements FsWatcher {
  final _controller = StreamController<FsChangeEvent>.broadcast();

  void emit(FsChangeType type, String path) =>
      _controller.add(FsChangeEvent(path: path, type: type));

  @override
  Stream<FsChangeEvent> watchTree(String path) => _controller.stream;
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
      );
      addTearDown(watcher.dispose);

      final batches = <Set<String>>[];
      watcher.onChanged.listen(batches.add);

      fs.emit(FsChangeType.created, '/repo/a.txt');
      fs.emit(FsChangeType.created, '/repo/sub/b.txt');
      fs.emit(FsChangeType.modified, '/repo/sub/c.txt');

      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(batches, [
        {'/repo', '/repo/sub'},
      ]);
    });

    test('poke() emits an empty set meaning full refresh', () async {
      final fs = _WatchableFs();
      final watcher = WorkspaceFsWatcher(
        fs: fs,
        root: '/repo',
        debounce: const Duration(milliseconds: 20),
      );
      addTearDown(watcher.dispose);

      final batches = <Set<String>>[];
      watcher.onChanged.listen(batches.add);

      watcher.poke();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(batches, [<String>{}]);
    });

    test('ignores churn inside noisy directories', () async {
      final fs = _WatchableFs();
      final watcher = WorkspaceFsWatcher(
        fs: fs,
        root: '/repo',
        debounce: const Duration(milliseconds: 20),
      );
      addTearDown(watcher.dispose);

      final batches = <Set<String>>[];
      watcher.onChanged.listen(batches.add);

      fs.emit(FsChangeType.created, '/repo/node_modules/x/index.js');
      fs.emit(FsChangeType.modified, '/repo/.dart_tool/package_config.json');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(batches, isEmpty);

      // A real source change still comes through.
      fs.emit(FsChangeType.created, '/repo/lib/main.dart');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(batches, [
        {'/repo/lib'},
      ]);
    });

    test('stops emitting after dispose', () async {
      final fs = _WatchableFs();
      final watcher = WorkspaceFsWatcher(
        fs: fs,
        root: '/repo',
        debounce: const Duration(milliseconds: 20),
      );

      var count = 0;
      watcher.onChanged.listen((_) => count++);
      watcher.dispose();

      fs.emit(FsChangeType.created, '/repo/a.txt');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(count, 0);
    });
  });
}
