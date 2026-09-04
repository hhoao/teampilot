import 'dart:async';

import 'package:path/path.dart' as p;

import '../../cubits/git_cubit.dart';
import '../../cubits/git_graph_cubit.dart';
import '../storage/runtime_context.dart';
import 'git_history_actions.dart';
import 'git_history_service.dart';
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
    GitGraphCubit Function(String root, RuntimeContext workContext)?
    graphCubitFactory,
    int maxRetained = 8,
  }) : _cubitFactory = cubitFactory ?? _defaultFactory,
       _graphFactory = graphCubitFactory ?? _defaultGraphFactory,
       _maxRetained = maxRetained;

  static GitCubit _defaultFactory(String root, RuntimeContext workContext) {
    final service =
        GitService.debugOverrideFactory?.call() ??
        GitService.forContext(workContext);
    return GitCubit(service: service)..setRepoRoot(root);
  }

  static GitGraphCubit _defaultGraphFactory(
    String root,
    RuntimeContext workContext,
  ) {
    final history =
        GitHistoryService.debugOverrideFactory?.call() ??
        GitHistoryService.forContext(workContext);
    final git =
        GitService.debugOverrideFactory?.call() ??
        GitService.forContext(workContext);
    final actions =
        GitHistoryActions.debugOverrideFactory?.call() ??
        GitHistoryActions.forContext(workContext);
    return GitGraphCubit(history: history, git: git, actions: actions);
  }

  final GitCubit Function(String root, RuntimeContext workContext)
  _cubitFactory;
  final GitGraphCubit Function(String root, RuntimeContext workContext)
  _graphFactory;
  final int _maxRetained;
  final p.Context _ctx = p.Context();

  /// Normalized `targetId:root` → cubit. Insertion order is the LRU order.
  final Map<String, GitCubit> _cubits = <String, GitCubit>{};

  /// Same keying as [_cubits]; independent LRU so graph panels never evict
  /// status cubits (and vice versa).
  final Map<String, GitGraphCubit> _graphCubits = <String, GitGraphCubit>{};

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

  /// Returns the retained graph cubit for [root] on [workContext], creating it
  /// on first access and warming it asynchronously.
  GitGraphCubit graphCubitFor(
    String root, {
    required RuntimeContext workContext,
  }) {
    final key = _cacheKey(root, workContext);
    final existing = _graphCubits.remove(key);
    // 已被外部路径（如 BlocProvider）关闭的保留实例必须弃用，否则面板拿到
    // closed cubit 后任何 emit 都会抛 StateError。
    if (existing != null && !existing.isClosed) {
      _graphCubits[key] = existing;
      return existing;
    }
    final cubit = _graphFactory(_ctx.normalize(root), workContext);
    unawaited(cubit.setRepoRoot(root));
    _graphCubits[key] = cubit;
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

  /// Refreshes the graph cubits for every [roots] entry on [workContext], so
  /// open graph panes track poll-driven status updates.
  ///
  /// Only cubits with a mounted pane ([GitGraphCubit.hasActiveListeners]) are
  /// refreshed — a graph refresh costs ~5 subprocesses (graph rows, status,
  /// branches, tags, stashes), so the poll must not warm graphs nobody is
  /// viewing. Panes create + warm their cubit via [graphCubitFor] on mount.
  void refreshGraphs(
    Iterable<String> roots, {
    required RuntimeContext workContext,
  }) {
    for (final root in roots) {
      if (root.isEmpty) continue;
      final cubit = _graphCubits[_cacheKey(root, workContext)];
      if (cubit == null || cubit.isClosed || !cubit.hasActiveListeners) {
        continue;
      }
      unawaited(cubit.refresh());
    }
  }

  void _evict() {
    while (_cubits.length > _maxRetained) {
      final oldestKey = _cubits.keys.first;
      _cubits.remove(oldestKey)?.close();
    }
    while (_graphCubits.length > _maxRetained) {
      final oldestEvictable = _oldestEvictableGraphKey();
      // 全部图 cubit 都有监听者（面板挂载中）时暂停淘汰，避免关闭在用面板。
      if (oldestEvictable == null) break;
      _graphCubits.remove(oldestEvictable)?.close();
    }
  }

  /// LRU 序里第一个没有监听者的图 cubit key；全被占用时返回 null。
  String? _oldestEvictableGraphKey() {
    for (final key in _graphCubits.keys) {
      if (!_graphCubits[key]!.hasActiveListeners) return key;
    }
    return null;
  }

  void dispose() {
    for (final cubit in _cubits.values) {
      cubit.close();
    }
    for (final cubit in _graphCubits.values) {
      cubit.close();
    }
    _cubits.clear();
    _graphCubits.clear();
  }
}
