import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../models/workspace_folder.dart';
import '../../models/workspace_topology.dart';
import '../session/session_lifecycle_service.dart';
import 'workspace_tools_context.dart';

/// One work-plane target in a workspace (local, ssh, wsl, …).
class WorkspaceTargetSlice extends Equatable {
  const WorkspaceTargetSlice({
    required this.targetId,
    required this.tools,
    required this.roots,
  });

  final String targetId;
  final WorkspaceToolsContext tools;
  final List<String> roots;

  @override
  List<Object?> get props => [targetId, tools, roots];
}

/// Resolved tools plane for one workspace tab: target context + filtered roots.
class WorkspaceToolsScopeState extends Equatable {
  const WorkspaceToolsScopeState({
    this.tools,
    this.roots = const [],
    this.targetSlices = const [],
    this.effectiveFolders = const [],
    this.resolving = true,
  });

  /// Active work-plane (follows cwd / session paths).
  final WorkspaceToolsContext? tools;

  /// Roots on [tools] — used by git panel and fs watcher.
  final List<String> roots;

  /// All targets in a mixed workspace; single entry otherwise.
  final List<WorkspaceTargetSlice> targetSlices;
  final List<WorkspaceFolder> effectiveFolders;
  final bool resolving;

  bool get isReady => tools != null && !resolving;

  bool get isMixed =>
      workspaceTopologyOf(effectiveFolders) == WorkspaceTopology.mixed;

  WorkspaceToolsScopeState copyWith({
    WorkspaceToolsContext? tools,
    List<String>? roots,
    List<WorkspaceTargetSlice>? targetSlices,
    List<WorkspaceFolder>? effectiveFolders,
    bool? resolving,
  }) =>
      WorkspaceToolsScopeState(
        tools: tools ?? this.tools,
        roots: roots ?? this.roots,
        targetSlices: targetSlices ?? this.targetSlices,
        effectiveFolders: effectiveFolders ?? this.effectiveFolders,
        resolving: resolving ?? this.resolving,
      );

  @override
  List<Object?> get props => [
    tools,
    roots,
    targetSlices,
    effectiveFolders,
    resolving,
  ];
}

/// Resolves [WorkspaceToolsContext] once per cwd / folder / session change.
class WorkspaceToolsScopeCubit extends Cubit<WorkspaceToolsScopeState> {
  WorkspaceToolsScopeCubit({required SessionLifecycleService lifecycle})
    : _lifecycle = lifecycle,
      super(const WorkspaceToolsScopeState());

  final SessionLifecycleService _lifecycle;
  int _syncGeneration = 0;

  Future<void> sync({
    required List<WorkspaceFolder> workspaceFolders,
    required String cwd,
    required List<String> additionalPaths,
    List<WorkspaceFolder>? sessionFolders,
  }) async {
    final generation = ++_syncGeneration;
    final folders = sessionFolders != null && sessionFolders.isNotEmpty
        ? sessionFolders
        : workspaceFolders;
    if (folders.isEmpty) {
      if (generation != _syncGeneration || isClosed) return;
      emit(const WorkspaceToolsScopeState(resolving: false));
      return;
    }
    // Stale-while-revalidate: keep the last resolved tools plane visible while
    // cwd/session folders re-resolve. Only block the panel on the first resolve.
    if (!isClosed && state.tools == null) {
      emit(state.copyWith(resolving: true));
    }

    final activeTools = await WorkspaceToolsContext.resolve(
      lifecycle: _lifecycle,
      folders: folders,
      paths: [cwd, ...additionalPaths],
    );
    if (generation != _syncGeneration || isClosed) return;

    final activeRoots = WorkspaceToolsContext.rootsOnTarget(
      folders: folders,
      targetId: activeTools.targetId,
      primaryPath: cwd,
      additionalPaths: additionalPaths,
      context: activeTools.context,
    );

    final topology = workspaceTopologyOf(folders);
    final slices = topology == WorkspaceTopology.mixed
        ? await _resolveMixedSlices(
            folders: folders,
            cwd: cwd,
            additionalPaths: additionalPaths,
            activeTools: activeTools,
          )
        : [
            WorkspaceTargetSlice(
              targetId: activeTools.targetId,
              tools: activeTools,
              roots: activeRoots,
            ),
          ];

    if (generation != _syncGeneration || isClosed) return;

    emit(
      WorkspaceToolsScopeState(
        tools: activeTools,
        roots: activeRoots,
        targetSlices: slices,
        effectiveFolders: folders,
        resolving: false,
      ),
    );
  }

  Future<List<WorkspaceTargetSlice>> _resolveMixedSlices({
    required List<WorkspaceFolder> folders,
    required String cwd,
    required List<String> additionalPaths,
    required WorkspaceToolsContext activeTools,
  }) async {
    final slices = <WorkspaceTargetSlice>[];
    for (final targetId in workspaceTargetIds(folders)) {
      final context = targetId == activeTools.targetId
          ? activeTools.context
          : await _lifecycle.resolveWorkContextForTargetId(targetId);
      final tools = targetId == activeTools.targetId
          ? activeTools
          : WorkspaceToolsContext(targetId: targetId, context: context);
      final roots = WorkspaceToolsContext.rootsForTarget(
        folders: folders,
        targetId: targetId,
        primaryPath: cwd,
        additionalPaths: additionalPaths,
        context: context,
      );
      if (roots.isEmpty) continue;
      slices.add(
        WorkspaceTargetSlice(targetId: targetId, tools: tools, roots: roots),
      );
    }
    return slices;
  }
}

/// Inherited access to the resolved workspace tools plane.
class WorkspaceToolsScope extends InheritedWidget {
  const WorkspaceToolsScope({
    required this.state,
    required super.child,
    super.key,
  });

  final WorkspaceToolsScopeState state;

  static WorkspaceToolsScopeState of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<WorkspaceToolsScope>();
    assert(scope != null, 'WorkspaceToolsScope not found in context');
    return scope!.state;
  }

  static WorkspaceToolsScopeState? maybeOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<WorkspaceToolsScope>()
          ?.state;

  @override
  bool updateShouldNotify(WorkspaceToolsScope oldWidget) =>
      oldWidget.state != state;
}
