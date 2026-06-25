import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../models/workspace_folder.dart';
import '../session/session_lifecycle_service.dart';
import 'workspace_tools_context.dart';

/// Resolved tools plane for one workspace tab: target context + filtered roots.
class WorkspaceToolsScopeState extends Equatable {
  const WorkspaceToolsScopeState({
    this.tools,
    this.roots = const [],
    this.effectiveFolders = const [],
    this.resolving = true,
  });

  final WorkspaceToolsContext? tools;
  final List<String> roots;
  final List<WorkspaceFolder> effectiveFolders;
  final bool resolving;

  bool get isReady => tools != null && !resolving;

  WorkspaceToolsScopeState copyWith({
    WorkspaceToolsContext? tools,
    List<String>? roots,
    List<WorkspaceFolder>? effectiveFolders,
    bool? resolving,
  }) =>
      WorkspaceToolsScopeState(
        tools: tools ?? this.tools,
        roots: roots ?? this.roots,
        effectiveFolders: effectiveFolders ?? this.effectiveFolders,
        resolving: resolving ?? this.resolving,
      );

  @override
  List<Object?> get props => [tools, roots, effectiveFolders, resolving];
}

/// Resolves [WorkspaceToolsContext] once per cwd / folder / session change.
class WorkspaceToolsScopeCubit extends Cubit<WorkspaceToolsScopeState> {
  WorkspaceToolsScopeCubit({required SessionLifecycleService lifecycle})
    : _lifecycle = lifecycle,
      super(const WorkspaceToolsScopeState());

  final SessionLifecycleService _lifecycle;

  Future<void> sync({
    required List<WorkspaceFolder> workspaceFolders,
    required String cwd,
    required List<String> additionalPaths,
    List<WorkspaceFolder>? sessionFolders,
  }) async {
    final folders = sessionFolders != null && sessionFolders.isNotEmpty
        ? sessionFolders
        : workspaceFolders;
    if (folders.isEmpty) {
      emit(const WorkspaceToolsScopeState(resolving: false));
      return;
    }
    if (!isClosed) emit(state.copyWith(resolving: true));
    final tools = await WorkspaceToolsContext.resolve(
      lifecycle: _lifecycle,
      folders: folders,
      paths: [cwd, ...additionalPaths],
    );
    if (isClosed) return;
    final roots = WorkspaceToolsContext.rootsOnTarget(
      folders: folders,
      targetId: tools.targetId,
      primaryPath: cwd,
      additionalPaths: additionalPaths,
      context: tools.context,
    );
    emit(
      WorkspaceToolsScopeState(
        tools: tools,
        roots: roots,
        effectiveFolders: folders,
        resolving: false,
      ),
    );
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
