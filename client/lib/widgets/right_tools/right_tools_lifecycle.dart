import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/file_tree_cubit.dart';
import '../../cubits/file_tree_root_mount.dart';
import '../../services/file_tree/workspace_file_tree_store.dart';
import '../../services/git/git_repo_store.dart';
import '../../services/io/workspace_fs_watcher.dart';
import '../../services/workspace/workspace_tools_context.dart';
import '../../services/workspace/workspace_tools_scope.dart';
import 'right_tools_tool_preferences.dart';

/// Resolved file-tree + disk-watch state for the right tools panel.
///
/// Side effects (store retention, [FileTreeCubit.mountRoots], watchers) are
/// owned by [RightToolsLifecycleHost] — never run during [Widget.build].
class RightToolsLifecycleData {
  const RightToolsLifecycleData({
    required this.scope,
    required this.fileTreeCubit,
    required this.pokeOnTurnEnd,
    required this.ensureFileTreeReady,
  });

  final WorkspaceToolsScopeState scope;
  final FileTreeCubit? fileTreeCubit;
  final VoidCallback pokeOnTurnEnd;

  /// Idempotent hook for [FileTreePanel] first mount (lazy tab) — mounts roots
  /// if the deferred workspace sync was skipped or raced ahead of the panel.
  final VoidCallback ensureFileTreeReady;
}

class RightToolsLifecycle extends InheritedWidget {
  const RightToolsLifecycle({
    required this.data,
    required super.child,
    super.key,
  });

  final RightToolsLifecycleData data;

  static RightToolsLifecycleData of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<RightToolsLifecycle>();
    assert(scope != null, 'RightToolsLifecycle not found in context');
    return scope!.data;
  }

  @override
  bool updateShouldNotify(RightToolsLifecycle oldWidget) =>
      oldWidget.data.scope != data.scope ||
      !identical(oldWidget.data.fileTreeCubit, data.fileTreeCubit);
}

/// Mounts file-tree cubits, FS watchers, and disk refresh for [RightToolsPanel].
class RightToolsLifecycleHost extends StatefulWidget {
  const RightToolsLifecycleHost({
    required this.cwd,
    required this.additionalPaths,
    required this.workspaceId,
    required this.preferences,
    required this.child,
    super.key,
  });

  final String cwd;
  final List<String> additionalPaths;
  final String workspaceId;
  final RightToolsToolPreferences preferences;
  final Widget child;

  @override
  State<RightToolsLifecycleHost> createState() => _RightToolsLifecycleHostState();
}

class _RightToolsLifecycleHostState extends State<RightToolsLifecycleHost> {
  WorkspaceFsWatcher? _fsWatcher;
  WorkspaceToolsScopeState? _scope;
  String? _lastTargetId;
  FileTreeCubit? _fileTreeCubit;
  List<FileTreeRootMount> _lastMounts = const [];

  StreamSubscription<Set<String>>? _diskWatchSub;
  Timer? _diskPollTimer;
  static const _diskPollInterval = Duration(seconds: 15);

  bool _scopeSyncScheduled = false;
  bool _diskRefreshScheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scheduleScopeSync();
  }

  @override
  void didUpdateWidget(covariant RightToolsLifecycleHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    final rootsChanged =
        widget.cwd != oldWidget.cwd ||
        !listEquals(widget.additionalPaths, oldWidget.additionalPaths);
    if (rootsChanged && _scope != null && _fileTreeCubit != null) {
      final tools = _scope!.tools;
      if (tools != null) {
        _rebuildWatcher(tools);
        _scheduleMountRoots(_fileTreeMounts(_scope!));
      }
    }
    if (rootsChanged ||
        widget.workspaceId != oldWidget.workspaceId ||
        widget.preferences != oldWidget.preferences) {
      _scheduleDiskRefresh();
    }
  }

  void _scheduleScopeSync() {
    if (_scopeSyncScheduled) return;
    _scopeSyncScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _scopeSyncScheduled = false;
      if (!mounted) return;
      _syncScope(WorkspaceToolsScope.of(context));
    });
  }

  void _scheduleDiskRefresh({bool afterInitialPaint = false}) {
    if (_diskRefreshScheduled) return;
    _diskRefreshScheduled = true;
    void run() {
      _diskRefreshScheduled = false;
      if (!mounted) return;
      _setupDiskRefresh();
    }
    if (afterInitialPaint) {
      _scheduleAfterFileTreePaintStagger(run);
    } else {
      SchedulerBinding.instance.addPostFrameCallback((_) => run());
    }
  }

  /// Waits for [RightToolsLifecycleHost] scope publish plus [FileTreePanel]'s
  /// header → filter → list stagger before running disk-side effects.
  void _scheduleAfterFileTreePaintStagger(void Function() action) {
    const frameCount = 5;
    void chain(int remaining) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (remaining <= 1) {
          action();
        } else {
          chain(remaining - 1);
        }
      });
    }

    chain(frameCount);
  }

  void _scheduleMountRoots(List<FileTreeRootMount> mounts) {
    if (mounts.isEmpty) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final cubit = _fileTreeCubit;
      if (cubit == null) return;
      unawaited(cubit.mountRoots(mounts));
    });
  }

  void _ensureFileTreeReady() {
    final cubit = _fileTreeCubit;
    if (cubit == null) return;
    final mounts = _lastMounts;
    if (cubit.state.rootPaths.isEmpty) {
      if (mounts.isNotEmpty) {
        unawaited(cubit.mountRoots(mounts));
      }
      return;
    }
    _warmFileTree();
  }

  void _syncScope(WorkspaceToolsScopeState scope) {
    final tools = scope.tools;
    if (tools == null) {
      _scope = scope;
      return;
    }

    final storeTargetId = scope.isMixed
        ? WorkspaceFileTreeStore.mixedTargetId
        : tools.targetId;
    final storeTargetChanged = storeTargetId != _lastTargetId;
    final mounts = _fileTreeMounts(scope);

    if (storeTargetChanged) {
      if (_lastTargetId != null) {
        context.read<WorkspaceFileTreeStore>().removeWorkspaceTarget(
          widget.workspaceId,
          _lastTargetId!,
        );
      }
      _lastTargetId = storeTargetId;
      final primaryFs = mounts.isNotEmpty
          ? mounts.first.filesystem
          : tools.context.filesystem;
      _fileTreeCubit = context.read<WorkspaceFileTreeStore>().cubitFor(
        widget.workspaceId,
        targetId: storeTargetId,
        fs: primaryFs,
      );
      _rebuildWatcher(tools);
      _scheduleMountRoots(mounts);
      _scheduleDiskRefresh(afterInitialPaint: true);
    } else if (_fileTreeCubit != null && !_mountListsEqual(_lastMounts, mounts)) {
      _scheduleMountRoots(mounts);
    }

    _lastMounts = mounts;
    _scope = scope;
    if (!mounted) return;
    // First cubit attach can coincide with workspace sidebar layout; publish on
    // the next frame so FileTreePanel does not mount in the same UI frame.
    if (storeTargetChanged) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  List<FileTreeRootMount> _fileTreeMounts(WorkspaceToolsScopeState scope) => [
    for (final slice in scope.targetSlices)
      for (final path in slice.roots)
        FileTreeRootMount(
          path: path,
          filesystem: slice.tools.context.filesystem,
          workContext: slice.tools.context,
        ),
  ];

  bool _mountListsEqual(
    List<FileTreeRootMount> a,
    List<FileTreeRootMount> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].path != b[i].path ||
          !identical(a[i].filesystem, b[i].filesystem)) {
        return false;
      }
    }
    return true;
  }

  void _rebuildWatcher(WorkspaceToolsContext tools) {
    _fsWatcher?.dispose();
    _fsWatcher = widget.cwd.isEmpty
        ? null
        : WorkspaceFsWatcher(
            fs: tools.context.filesystem,
            root: widget.cwd,
          );
  }

  void _setupDiskRefresh() {
    _diskWatchSub?.cancel();
    _diskWatchSub = null;
    _diskPollTimer?.cancel();
    _diskPollTimer = null;

    final needsFileTree = widget.preferences.fileTreeVisible;
    final needsGit = widget.preferences.gitVisible;
    if (!needsFileTree && !needsGit) return;

    if (needsFileTree) _warmFileTree();
    if (needsGit) _warmGit();

    final watcher = _fsWatcher;
    if (watcher?.isSupported ?? false) {
      _diskWatchSub = watcher!.onChanged.listen(_onDiskChanged);
    } else {
      _diskPollTimer = Timer.periodic(
        _diskPollInterval,
        (_) => _onDiskPoll(),
      );
    }
  }

  void _onDiskChanged(Set<String> changedDirs) {
    if (widget.preferences.fileTreeVisible) {
      _refreshFileTree(changedDirs);
    }
    if (widget.preferences.gitVisible) {
      _warmGit();
    }
  }

  void _onDiskPoll() {
    if (widget.preferences.fileTreeVisible) {
      _warmFileTree();
    }
    if (widget.preferences.gitVisible) {
      _warmGit();
    }
  }

  void _refreshFileTree(Set<String> changedDirs) {
    final cubit = _fileTreeCubit;
    if (cubit == null) return;
    if (changedDirs.isEmpty) {
      unawaited(cubit.refresh());
    } else {
      unawaited(cubit.refreshPaths(changedDirs));
    }
  }

  void _warmFileTree() {
    final cubit = _fileTreeCubit;
    if (cubit == null) return;
    final state = cubit.state;
    if (state.rootPaths.isEmpty) {
      final mounts = _lastMounts;
      if (mounts.isNotEmpty) {
        unawaited(cubit.mountRoots(mounts));
      }
      return;
    }
    final cold = state.rootPaths.any(
      (root) => state.dirCache[root] == null,
    );
    if (cold) {
      unawaited(cubit.refresh());
    }
  }

  void _warmGit() {
    final tools = _scope?.tools?.context;
    if (tools == null) return;
    context.read<GitRepoStore>().refreshAll(
      _scope!.roots,
      workContext: tools,
    );
  }

  void _pokeOnTurnEnd() => _fsWatcher?.poke();

  @override
  void dispose() {
    _diskWatchSub?.cancel();
    _diskPollTimer?.cancel();
    _fsWatcher?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = _scope ?? WorkspaceToolsScope.maybeOf(context);
    final data = RightToolsLifecycleData(
      scope: scope ?? const WorkspaceToolsScopeState(resolving: true),
      fileTreeCubit: _fileTreeCubit,
      pokeOnTurnEnd: _pokeOnTurnEnd,
      ensureFileTreeReady: _ensureFileTreeReady,
    );
    return RightToolsLifecycle(data: data, child: widget.child);
  }
}
