import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/chat_cubit.dart';
import '../../cubits/file_tree_cubit.dart';
import '../../cubits/file_tree_root_mount.dart';
import '../../cubits/member_presence_cubit.dart';
import '../../models/layout_preferences.dart';
import '../../services/file_tree/workspace_file_tree_store.dart';
import '../../services/git/git_repo_store.dart';
import '../../services/io/workspace_fs_watcher.dart';
import '../../services/workspace/workspace_tools_context.dart';
import '../../services/workspace/workspace_tools_scope.dart';
import '../../utils/app_keys.dart';
import 'right_tools_tool_views.dart';

class RightToolsPanel extends StatefulWidget {
  const RightToolsPanel({
    required this.cwd,
    required this.workspaceId,
    this.toolsScopeId,
    this.additionalPaths = const [],
    this.preferences = const LayoutPreferences(),
    this.panelKey = AppKeys.rightToolsPanel,
    this.dismissDrawerOnAction = false,
    this.isPersonalWorkspace = false,
    super.key,
  });

  final LayoutPreferences preferences;
  final Key panelKey;
  final bool dismissDrawerOnAction;

  /// Solo workspace workbench — hide team members / mailbox tooling.
  final bool isPersonalWorkspace;

  /// Working directory the file tree / git panel operate on. Supplied by the
  /// caller (the workspace context), decoupling the tools from chat-session tab
  /// state.
  final String cwd;

  /// Extra workspace folders (beyond [cwd]) for multi-root file tree / source
  /// control. Empty for single-folder workspaces.
  final List<String> additionalPaths;

  /// Workspace this tools panel belongs to; scopes [WorkspaceFileTreeStore] retention.
  final String workspaceId;

  /// Per title-bar tab scope for tool-tab selection; defaults to [workspaceId].
  final String? toolsScopeId;

  String get _toolsScopeId => toolsScopeId ?? workspaceId;

  @override
  State<RightToolsPanel> createState() => _RightToolsPanelState();
}

class _RightToolsPanelState extends State<RightToolsPanel> {
  ChatCubit? _chatCubit;
  MemberPresenceCubit? _presenceCubit;

  /// Single recursive watch on the workspace cwd, shared by the file-tree and
  /// source-control panels so they refresh live on disk changes (e.g. files an
  /// agent writes in the terminal) instead of going stale.
  WorkspaceFsWatcher? _fsWatcher;

  WorkspaceToolsScopeState? _scope;
  String? _lastTargetId;

  FileTreeCubit? _fileTreeCubit;
  StreamSubscription<Set<String>>? _diskWatchSub;
  Timer? _diskPollTimer;
  static const _diskPollInterval = Duration(seconds: 15);

  @override
  void initState() {
    super.initState();
    _setupDiskRefresh();
  }

  WorkspaceToolsScopeState _requireScope(BuildContext context) {
    final scope = WorkspaceToolsScope.of(context);
    _applyScope(scope);
    return scope;
  }

  void _applyScope(WorkspaceToolsScopeState scope) {
    final tools = scope.tools;
    if (tools == null) return;

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
      unawaited(_fileTreeCubit!.mountRoots(mounts));
      _setupDiskRefresh();
    } else if (_fileTreeCubit != null && !_mountListsEqual(_lastMounts, mounts)) {
      unawaited(_fileTreeCubit!.mountRoots(mounts));
    }
    _lastMounts = mounts;
    _scope = scope;
  }

  List<FileTreeRootMount> _lastMounts = const [];

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

  @override
  void didUpdateWidget(covariant RightToolsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final rootsChanged =
        widget.cwd != oldWidget.cwd ||
        !listEquals(widget.additionalPaths, oldWidget.additionalPaths);
    if (rootsChanged) {
      final scope = _scope;
      final tools = scope?.tools;
      if (tools != null && _fileTreeCubit != null) {
        _rebuildWatcher(tools);
        final mounts = _fileTreeMounts(scope!);
        unawaited(_fileTreeCubit!.mountRoots(mounts));
      }
    }
    if (rootsChanged ||
        widget.workspaceId != oldWidget.workspaceId ||
        widget.preferences.gitVisible != oldWidget.preferences.gitVisible ||
        widget.preferences.fileTreeVisible !=
            oldWidget.preferences.fileTreeVisible) {
      _setupDiskRefresh();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final chatCubit = context.read<ChatCubit>();
    final presenceCubit = context.read<MemberPresenceCubit>();
    if (!identical(_chatCubit, chatCubit)) {
      _presenceCubit?.detachPresenceUi(this);
      _chatCubit = chatCubit;
      _presenceCubit = presenceCubit;
      presenceCubit.attachPresenceUi(this);
    }
  }

  /// Keeps the file tree and git panels warm while their tools are enabled.
  /// Uses the shared [_fsWatcher] when available, else a periodic poll
  /// (SSH/Android). One subscription serves both consumers.
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

  /// Empty [changedDirs] = unknown scope (e.g. turn-end poke) → full refresh.
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
    // Cold start: mount roots first; refresh only when root listings are missing.
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

  /// Pokes the watcher when any session leaves the working set (a turn ended,
  /// so the agent has likely just written files). Cheap no-op on watch-capable
  /// backends; the real change path for SSH/Android where no disk events fire.
  void _pokeOnTurnEnd() => _fsWatcher?.poke();

  @override
  void dispose() {
    _diskWatchSub?.cancel();
    _diskPollTimer?.cancel();
    _fsWatcher?.dispose();
    _presenceCubit?.detachPresenceUi(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = _requireScope(context);
    final tools = scope.tools;
    if (!scope.isReady || tools == null) {
      return const SizedBox.shrink();
    }

    return RightToolsWorkingTurnListener(
      onTurnEnd: _pokeOnTurnEnd,
      child: RightToolsPresenceTeamSync(
        isPersonalWorkspace: widget.isPersonalWorkspace,
        child: Container(
          key: widget.panelKey,
          child: RightToolsToolViews(
            preferences: widget.preferences,
            cwd: widget.cwd,
            workspaceId: widget.workspaceId,
            toolsScopeId: widget._toolsScopeId,
            isPersonalWorkspace: widget.isPersonalWorkspace,
            dismissDrawerOnAction: widget.dismissDrawerOnAction,
            fileTreeCubit: _fileTreeCubit!,
            workContext: tools.context,
            scope: scope,
          ),
        ),
      ),
    );
  }
}
