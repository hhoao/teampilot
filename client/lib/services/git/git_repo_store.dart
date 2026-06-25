import 'package:path/path.dart' as p;

import '../../cubits/git_cubit.dart';
import '../storage/runtime_context.dart';
import 'git_service.dart';

/// App-level registry of long-lived [GitCubit]s, one per repository root and
/// storage target.
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
    GitCubit Function(String root, RuntimeContext workContext)? cubitFactory,
    int maxRetained = 8,
  }) : _cubitFactory = cubitFactory ?? _defaultFactory,
       _maxRetained = maxRetained;

  static GitCubit _defaultFactory(String root, RuntimeContext workContext) {
    final service =
        GitService.debugOverrideFactory?.call() ??
        GitService.forContext(workContext);
    return GitCubit(service: service)..setRepoRoot(root);
  }

  final GitCubit Function(String root, RuntimeContext workContext) _cubitFactory;
  final int _maxRetained;
  final p.Context _ctx = p.Context();

  /// Normalized `targetId:root` → cubit. Insertion order is the LRU order.
  final Map<String, GitCubit> _cubits = <String, GitCubit>{};

  static String _cacheKey(String root, RuntimeContext workContext) {
    final normalized = p.Context(style: p.Style.posix).normalize(root);
    return '${workContext.target.id}:$normalized';
  }

  /// Returns the retained cubit for [root] on [workContext], creating (and
  /// warming) it on first access.
  GitCubit cubitFor(String root, {required RuntimeContext workContext}) {
    final key = _cacheKey(root, workContext);
    final existing = _cubits.remove(key);
    if (existing != null) {
      _cubits[key] = existing;
      return existing;
    }
    final cubit = _cubitFactory(_ctx.normalize(root), workContext);
    _cubits[key] = cubit;
    _evict();
    return cubit;
  }

  /// Triggers a coalesced refresh for every [roots] entry on [workContext].
  void refreshAll(
    Iterable<String> roots, {
    required RuntimeContext workContext,
  }) {
    for (final root in roots) {
      if (root.isEmpty) continue;
      cubitFor(root, workContext: workContext).refresh();
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
