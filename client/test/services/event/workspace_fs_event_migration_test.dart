import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/event/async_dispatcher.dart';
import 'package:teampilot/services/event/dispatcher.dart';
import 'package:teampilot/services/event/workspace_fs_event.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/io/workspace_fs_watcher.dart';

import '../../support/in_memory_filesystem.dart';

/// In-memory filesystem that can push change events, mirroring the fake in
/// `workspace_fs_watcher_test.dart`, so the relay path can be driven with a
/// real (non-poke) batch without touching the disk.
class _WatchableFs extends InMemoryFilesystem implements FsWatcher {
  final StreamController<FsChangeEvent> _controller =
      StreamController<FsChangeEvent>.broadcast();

  void emit(FsChangeType type, String path) =>
      _controller.add(FsChangeEvent(path: path, type: type));

  @override
  FsTreeWatch watchTree(String path) => FsTreeWatch(
    events: _controller.stream,
    close: () async {},
  );
}

void main() {
  test('fs change event carries batch and root', () async {
    final d = AsyncDispatcher()..start();
    final received = <WorkspaceFsChangedEvent>[];
    d.registerFamily<WorkspaceFsKind>(
      WorkspaceFsKind.changed.runtimeType,
      _Handler(received),
    );

    d.dispatch(
      WorkspaceFsChangedEvent(
        root: '/w/a',
        batch: (changedDirs: const {'/w/a/lib'}, structural: true),
        timestamp: DateTime(2026),
      ),
    );
    await d.stop();

    expect(received.single.root, '/w/a');
    expect(received.single.batch.structural, isTrue);
  });

  test('watcher wired to a dispatcher still delivers batches on onChanged', () async {
    // Behavior-equivalence relay: with a dispatcher attached, _emit()
    // publishes a WorkspaceFsChangedEvent and the construction-registered
    // relay handler copies it back into the local controller, so onChanged
    // subscribers see identical batches with zero consumer changes.
    final d = AsyncDispatcher()..start();
    final fs = _WatchableFs();
    final watcher = WorkspaceFsWatcher(
      fs: fs,
      root: '/w/a',
      debounce: const Duration(milliseconds: 20),
      autoStart: true,
      dispatcher: d,
    );

    final batches = <FsChangeBatch>[];
    watcher.onChanged.listen(batches.add);

    fs.emit(FsChangeType.created, '/w/a/lib/new_file.dart');

    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(batches.single.changedDirs, {'/w/a/lib'});
    expect(batches.single.structural, isTrue);

    await watcher.stopAndDispose();
    await d.stop();
  });

  test('disposed watcher no longer relays dispatcher events', () async {
    // Leak regression (Task 4 lesson): the right-tools lifecycle constructs a
    // fresh watcher per cwd change and disposes the old one, while the
    // app-lifetime dispatcher outlives both. The disposed watcher's relay must
    // be unregistered so a new watcher's events cannot reach its dead
    // controller.
    final d = AsyncDispatcher()..start();
    final watcher = WorkspaceFsWatcher(
      fs: InMemoryFilesystem(),
      root: '/w/old',
      dispatcher: d,
    );
    final stale = <FsChangeBatch>[];
    watcher.onChanged.listen(stale.add);
    await watcher.stopAndDispose();

    final fresh = <WorkspaceFsChangedEvent>[];
    d.registerFamily<WorkspaceFsKind>(
      WorkspaceFsKind.changed.runtimeType,
      _Handler(fresh),
    );

    d.dispatch(
      WorkspaceFsChangedEvent(
        root: '/w/new',
        batch: (changedDirs: const {'/w/new'}, structural: true),
        timestamp: DateTime(2026),
      ),
    );
    await d.stop();
    await Future<void>.delayed(Duration.zero);

    expect(stale, isEmpty);
    expect(fresh.single.root, '/w/new');
  });
}

class _Handler implements EventHandler<WorkspaceFsChangedEvent> {
  _Handler(this.events);

  final List<WorkspaceFsChangedEvent> events;

  @override
  void handle(WorkspaceFsChangedEvent event) => events.add(event);
}
