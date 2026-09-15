import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/right_tool_open_set.dart';

class WorkspaceToolsState extends Equatable {
  const WorkspaceToolsState({this.openSet = const RightToolOpenSet()});

  final RightToolOpenSet openSet;

  WorkspaceToolsState copyWith({RightToolOpenSet? openSet}) =>
      WorkspaceToolsState(openSet: openSet ?? this.openSet);

  @override
  List<Object?> get props => [openSet];
}

class WorkspaceToolsCubit extends Cubit<WorkspaceToolsState> {
  WorkspaceToolsCubit({
    RightToolOpenSet initial = const RightToolOpenSet(),
    void Function(RightToolOpenSet set)? persist,
  }) : _persist = persist,
       super(WorkspaceToolsState(openSet: initial));

  final void Function(RightToolOpenSet set)? _persist;

  /// [scopeId] is ignored; the open set is global.
  List<String> openIdsFor(String scopeId) =>
      List<String>.unmodifiable(state.openSet.openIds);

  /// [scopeId] is ignored; the open set is global.
  String? selectedIdFor(String scopeId) => state.openSet.selectedId;

  void hydrate(RightToolOpenSet set) {
    if (set == state.openSet) return;
    emit(state.copyWith(openSet: set));
  }

  /// [scopeId] is ignored; the open set is global.
  void ensureOpenAndSelect(String scopeId, String toolId) {
    _apply(state.openSet.opened(toolId));
  }

  /// [scopeId] is ignored; the open set is global.
  void seedTeamDefaults(String scopeId, Iterable<String> catalogIds) {
    _apply(state.openSet.seededForTeam(catalogIds));
  }

  /// [scopeId] is ignored; the open set is global.
  void selectTool(String scopeId, String toolId) {
    _apply(state.openSet.selected(toolId));
  }

  /// [scopeId] is ignored; the open set is global.
  void closeTool(
    String scopeId,
    String toolId, {
    Iterable<String> catalog = const [],
  }) {
    final effectiveCatalog = catalog.isEmpty ? state.openSet.openIds : catalog;
    _apply(state.openSet.closed(toolId, catalog: effectiveCatalog));
  }

  /// Catalog membership is a display filter. Remembered ids stay.
  /// [scopeId] and [availableIds] are ignored; the open set is global.
  void pruneToAvailable(String scopeId, Iterable<String> availableIds) {}

  /// Global remembered set survives workspace-tab close.
  /// [scopeId] is ignored; the open set is global.
  void removeWorkspace(String scopeId) {}

  void _apply(RightToolOpenSet next) {
    if (next == state.openSet) return;
    emit(state.copyWith(openSet: next));
    _persist?.call(next);
  }
}
