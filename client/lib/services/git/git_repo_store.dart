import 'package:path/path.dart' as p;

import '../../cubits/git_cubit.dart';

/// App-level registry of long-lived [GitCubit]s, one per repository root.
///
/// The source-control panel is rebuilt every time its tool tab is selected
/// (the tab switcher only mounts the active view). If each panel owned its own
/// cubit, every open would re-run `git status` from scratch and flash a spinner.
/// Instead the cubit lives here, outliving the panel: reopening a repo shows the
/// last-known status instantly while a background poll refreshes it in place —
/// the "status cache outlives the view" model orca uses.
///
/// A small LRU bound keeps memory flat across a long session; a workspace's
/// folders are always among the most-recently-used, so they are never evicted
/// while in view.
class GitRepoStore {
  GitRepoStore({
    GitCubit Function(String root)? cubitFactory,
    int maxRetained = 8,
  }) : _cubitFactory = cubitFactory ?? _defaultFactory,
       _maxRetained = maxRetained;

  static GitCubit _defaultFactory(String root) =>
      GitCubit()..setRepoRoot(root);

  final GitCubit Function(String root) _cubitFactory;
  final int _maxRetained;
  final p.Context _ctx = p.Context();

  /// Normalized root → cubit. Insertion order is the LRU order: re-accessing a
  /// root moves it to the end (most-recently-used).
  final Map<String, GitCubit> _cubits = <String, GitCubit>{};

  /// Returns the retained cubit for [root], creating (and warming) it on first
  /// access. Accessing a root marks it most-recently-used.
  GitCubit cubitFor(String root) {
    final key = _ctx.normalize(root);
    final existing = _cubits.remove(key);
    if (existing != null) {
      _cubits[key] = existing; // bump to most-recently-used
      return existing;
    }
    final cubit = _cubitFactory(key);
    _cubits[key] = cubit;
    _evict();
    return cubit;
  }

  /// Triggers a coalesced refresh for every [roots] entry, creating cubits as
  /// needed. Used to warm a workspace's folders the moment its tools mount, so
  /// the source-control tab is already populated by the time it is opened.
  void refreshAll(Iterable<String> roots) {
    for (final root in roots) {
      if (root.isEmpty) continue;
      cubitFor(root).refresh();
    }
  }

  void _evict() {
    while (_cubits.length > _maxRetained) {
      final oldestKey = _cubits.keys.first;
      _cubits.remove(oldestKey)?.close();
    }
  }

  void dispose() {
    for (final cubit in _cubits.values) {
      cubit.close();
    }
    _cubits.clear();
  }
}
