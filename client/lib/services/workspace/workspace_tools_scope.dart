import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../models/workspace_folder.dart';
import '../../models/workspace_topology.dart';
import '../../utils/logging/logger_utils.dart';
import '../session/session_lifecycle_service.dart';
import '../storage/runtime_context.dart';
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
    this.failedTargetIds = const [],
    this.resolveError,
  });

  /// Active work-plane (follows cwd / session paths).
  final WorkspaceToolsContext? tools;

  /// Roots on [tools] — used by git panel and fs watcher.
  final List<String> roots;

  /// All targets in a mixed workspace; single entry otherwise.
  final List<WorkspaceTargetSlice> targetSlices;
  final List<WorkspaceFolder> effectiveFolders;
  final bool resolving;

  /// Targets that could not be resolved (e.g. unreachable SSH).
  final List<String> failedTargetIds;

  /// Non-null when at least one target failed; UI may still be ready if another
  /// target succeeded.
  final String? resolveError;

  bool get isReady => tools != null && !resolving;

  bool get isMixed =>
      workspaceTopologyOf(effectiveFolders) == WorkspaceTopology.mixed;

  WorkspaceToolsScopeState copyWith({
    WorkspaceToolsContext? tools,
    List<String>? roots,
    List<WorkspaceTargetSlice>? targetSlices,
    List<WorkspaceFolder>? effectiveFolders,
    bool? resolving,
    List<String>? failedTargetIds,
    String? resolveError,
    bool clearResolveError = false,
  }) => WorkspaceToolsScopeState(
    tools: tools ?? this.tools,
    roots: roots ?? this.roots,
    targetSlices: targetSlices ?? this.targetSlices,
    effectiveFolders: effectiveFolders ?? this.effectiveFolders,
    resolving: resolving ?? this.resolving,
    failedTargetIds: failedTargetIds ?? this.failedTargetIds,
    resolveError: clearResolveError
        ? null
        : (resolveError ?? this.resolveError),
  );

  @override
  List<Object?> get props => [
    tools,
    roots,
    targetSlices,
    effectiveFolders,
    resolving,
    failedTargetIds,
    resolveError,
  ];
}

/// Resolves [WorkspaceToolsContext] once per cwd / folder / session change.
class WorkspaceToolsScopeCubit extends Cubit<WorkspaceToolsScopeState> {
  WorkspaceToolsScopeCubit({
    required SessionLifecycleService lifecycle,
    Duration resolveTimeout = const Duration(seconds: 12),
  }) : _lifecycle = lifecycle,
       _resolveTimeout = resolveTimeout,
       super(const WorkspaceToolsScopeState());

  final SessionLifecycleService _lifecycle;
  final Duration _resolveTimeout;
  int _syncGeneration = 0;

  List<WorkspaceFolder>? _lastWorkspaceFolders;
  String? _lastCwd;
  List<String>? _lastAdditionalPaths;
  List<WorkspaceFolder>? _lastSessionFolders;

  /// Re-runs the last [sync] (e.g. after SSH comes back).
  Future<void> retry() async {
    final folders = _lastWorkspaceFolders;
    final cwd = _lastCwd;
    final additional = _lastAdditionalPaths;
    if (folders == null || cwd == null || additional == null) return;
    await sync(
      workspaceFolders: folders,
      cwd: cwd,
      additionalPaths: additional,
      sessionFolders: _lastSessionFolders,
    );
  }

  Future<void> sync({
    required List<WorkspaceFolder> workspaceFolders,
    required String cwd,
    required List<String> additionalPaths,
    List<WorkspaceFolder>? sessionFolders,
  }) async {
    final generation = ++_syncGeneration;
    _lastWorkspaceFolders = workspaceFolders;
    _lastCwd = cwd;
    _lastAdditionalPaths = additionalPaths;
    _lastSessionFolders = sessionFolders;

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
      emit(state.copyWith(resolving: true, clearResolveError: true));
    }

    final failed = <String>{};
    final activeTools = await _resolveActiveTools(
      folders: folders,
      cwd: cwd,
      additionalPaths: additionalPaths,
      failed: failed,
    );
    if (generation != _syncGeneration || isClosed) return;

    if (activeTools == null) {
      emit(
        WorkspaceToolsScopeState(
          effectiveFolders: folders,
          resolving: false,
          failedTargetIds: failed.toList(growable: false),
          resolveError: 'Could not open workspace tools',
        ),
      );
      return;
    }

    final activeRoots = WorkspaceToolsContext.rootsOnTarget(
      folders: folders,
      targetId: activeTools.targetId,
      primaryPath: cwd,
      additionalPaths: additionalPaths,
      context: activeTools.context,
    );
    final activeSlice = WorkspaceTargetSlice(
      targetId: activeTools.targetId,
      tools: activeTools,
      roots: activeRoots,
    );

    // Publish the active plane immediately so a slow/unreachable remote does
    // not block local file tree / git while mixed slices finish resolving.
    if (generation != _syncGeneration || isClosed) return;
    emit(
      WorkspaceToolsScopeState(
        tools: activeTools,
        roots: activeRoots,
        targetSlices: [activeSlice],
        effectiveFolders: folders,
        resolving: false,
        failedTargetIds: failed.toList(growable: false),
        resolveError: failed.isEmpty
            ? null
            : 'Some workspace machines could not be reached',
      ),
    );

    final topology = workspaceTopologyOf(folders);
    if (topology != WorkspaceTopology.mixed) return;

    final slices = await _resolveMixedSlices(
      folders: folders,
      cwd: cwd,
      additionalPaths: additionalPaths,
      activeTools: activeTools,
      failed: failed,
    );
    if (generation != _syncGeneration || isClosed) return;

    final failedList = failed.toList(growable: false);
    emit(
      WorkspaceToolsScopeState(
        tools: activeTools,
        roots: activeRoots,
        targetSlices: slices.isEmpty ? [activeSlice] : slices,
        effectiveFolders: folders,
        resolving: false,
        failedTargetIds: failedList,
        resolveError: failedList.isEmpty
            ? null
            : 'Some workspace machines could not be reached',
      ),
    );
  }

  Future<WorkspaceToolsContext?> _resolveActiveTools({
    required List<WorkspaceFolder> folders,
    required String cwd,
    required List<String> additionalPaths,
    required Set<String> failed,
  }) async {
    final preferredTargetId =
        targetIdForFolderPaths(folders, [
          cwd,
          ...additionalPaths,
        ], matchSubpaths: true) ??
        folders.first.targetId;

    final preferred = await _tryResolveTarget(preferredTargetId);
    if (preferred != null) {
      return WorkspaceToolsContext(
        targetId: preferredTargetId,
        context: preferred,
      );
    }
    failed.add(preferredTargetId);

    for (final targetId in _fallbackTargetOrder(folders, preferredTargetId)) {
      if (failed.contains(targetId)) continue;
      final context = await _tryResolveTarget(targetId);
      if (context != null) {
        return WorkspaceToolsContext(targetId: targetId, context: context);
      }
      failed.add(targetId);
    }
    return null;
  }

  /// Prefer local / already-listed targets after the preferred target fails.
  List<String> _fallbackTargetOrder(
    List<WorkspaceFolder> folders,
    String preferredTargetId,
  ) {
    final ids = workspaceTargetIds(folders);
    final ordered = <String>[];
    for (final id in ids) {
      if (id == preferredTargetId) continue;
      if (id == WorkspaceFolder.localTargetId) {
        ordered.insert(0, id);
      } else {
        ordered.add(id);
      }
    }
    return ordered;
  }

  Future<List<WorkspaceTargetSlice>> _resolveMixedSlices({
    required List<WorkspaceFolder> folders,
    required String cwd,
    required List<String> additionalPaths,
    required WorkspaceToolsContext activeTools,
    required Set<String> failed,
  }) async {
    final slices = <WorkspaceTargetSlice>[];
    for (final targetId in workspaceTargetIds(folders)) {
      RuntimeContext? context;
      WorkspaceToolsContext tools;
      if (targetId == activeTools.targetId) {
        context = activeTools.context;
        tools = activeTools;
      } else {
        context = await _tryResolveTarget(targetId);
        if (context == null) {
          failed.add(targetId);
          continue;
        }
        tools = WorkspaceToolsContext(targetId: targetId, context: context);
      }
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

  Future<RuntimeContext?> _tryResolveTarget(String targetId) async {
    try {
      return await _lifecycle
          .resolveWorkContextForTargetId(targetId)
          .timeout(_resolveTimeout);
    } on Object catch (e, st) {
      AppLogger.instance.w(
        'Workspace tools target resolve failed: $targetId ($e)',
        error: e,
        stackTrace: st,
      );
      return null;
    }
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
      context.dependOnInheritedWidgetOfExactType<WorkspaceToolsScope>()?.state;

  @override
  bool updateShouldNotify(WorkspaceToolsScope oldWidget) =>
      oldWidget.state != state;
}
