import 'dispatcher.dart';
import '../io/workspace_fs_watcher.dart' show FsChangeBatch;

/// Family kind for the central dispatcher. Single-member: the rich payload
/// (root + batch) stays on the event itself — the dispatcher only routes.
enum WorkspaceFsKind { changed }

/// A debounced filesystem change batch from a [WorkspaceFsWatcher], flowing
/// through the central [Dispatcher].
///
/// [batch] is the watcher's change record: the set of directory paths whose
/// listings may have changed (empty = full refresh) and whether any
/// contributing event was structural (created/deleted). See the `FsChangeBatch`
/// typedef for the full contract.
class WorkspaceFsChangedEvent implements DispatcherEvent<WorkspaceFsKind> {
  const WorkspaceFsChangedEvent({
    required this.root,
    required this.batch,
    required this.timestamp,
  });

  /// The watched workspace root (the emitting watcher's `root`).
  final String root;

  /// The debounced change batch.
  final FsChangeBatch batch;

  /// When the batch was emitted (the watcher's debounce flush moment).
  @override
  final DateTime timestamp;

  @override
  WorkspaceFsKind get eventKind => WorkspaceFsKind.changed;
}
