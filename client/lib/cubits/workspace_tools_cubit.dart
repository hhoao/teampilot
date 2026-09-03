import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Per-scope right-tools UI state: which tool tabs are open and which is
/// selected. Keyed by tab scope id so each open workspace remembers its own
/// set across workspace switches. Panel width/visibility stay global in
/// [LayoutCubit] — this cubit only owns the open-tab set.
class WorkspaceToolsState extends Equatable {
  const WorkspaceToolsState({
    this.openIdsByScope = const {},
    this.selectedIdByScope = const {},
  });

  final Map<String, List<String>> openIdsByScope;
  final Map<String, String?> selectedIdByScope;

  WorkspaceToolsState copyWith({
    Map<String, List<String>>? openIdsByScope,
    Map<String, String?>? selectedIdByScope,
  }) => WorkspaceToolsState(
    openIdsByScope: openIdsByScope ?? this.openIdsByScope,
    selectedIdByScope: selectedIdByScope ?? this.selectedIdByScope,
  );

  @override
  List<Object?> get props => [openIdsByScope, selectedIdByScope];
}

class WorkspaceToolsCubit extends Cubit<WorkspaceToolsState> {
  WorkspaceToolsCubit() : super(const WorkspaceToolsState());

  List<String> openIdsFor(String scopeId) =>
      List<String>.unmodifiable(state.openIdsByScope[scopeId] ?? const []);

  String? selectedIdFor(String scopeId) => state.selectedIdByScope[scopeId];

  /// Opens [toolId] if needed and selects it.
  void ensureOpenAndSelect(String scopeId, String toolId) {
    final open = List<String>.of(state.openIdsByScope[scopeId] ?? const []);
    final selected = state.selectedIdByScope[scopeId];
    var changed = false;
    if (!open.contains(toolId)) {
      open.add(toolId);
      changed = true;
    }
    if (selected != toolId) {
      changed = true;
    }
    if (!changed) return;
    emit(
      state.copyWith(
        openIdsByScope: Map<String, List<String>>.of(state.openIdsByScope)
          ..[scopeId] = open,
        selectedIdByScope: Map<String, String?>.of(state.selectedIdByScope)
          ..[scopeId] = toolId,
      ),
    );
  }

  /// Opens [toolIds] when the scope has no open tabs yet (first visit).
  void openDefaultsIfEmpty(
    String scopeId,
    List<String> toolIds, {
    String? selectId,
  }) {
    if (toolIds.isEmpty) return;
    final existing = state.openIdsByScope[scopeId];
    if (existing != null && existing.isNotEmpty) return;
    final open = List<String>.of(toolIds);
    final selected =
        selectId != null && open.contains(selectId) ? selectId : open.first;
    emit(
      state.copyWith(
        openIdsByScope: Map<String, List<String>>.of(state.openIdsByScope)
          ..[scopeId] = open,
        selectedIdByScope: Map<String, String?>.of(state.selectedIdByScope)
          ..[scopeId] = selected,
      ),
    );
  }

  void selectTool(String scopeId, String toolId) {
    final open = state.openIdsByScope[scopeId] ?? const <String>[];
    if (!open.contains(toolId)) {
      ensureOpenAndSelect(scopeId, toolId);
      return;
    }
    if (selectedIdFor(scopeId) == toolId) return;
    emit(
      state.copyWith(
        selectedIdByScope: Map<String, String?>.of(state.selectedIdByScope)
          ..[scopeId] = toolId,
      ),
    );
  }

  void closeTool(String scopeId, String toolId) {
    final open = List<String>.of(state.openIdsByScope[scopeId] ?? const []);
    final index = open.indexOf(toolId);
    if (index < 0) return;
    open.removeAt(index);
    String? selected = state.selectedIdByScope[scopeId];
    if (selected == toolId) {
      if (open.isEmpty) {
        selected = null;
      } else if (index > 0) {
        selected = open[index - 1];
      } else {
        selected = open.first;
      }
    }
    emit(
      state.copyWith(
        openIdsByScope: Map<String, List<String>>.of(state.openIdsByScope)
          ..[scopeId] = open,
        selectedIdByScope: Map<String, String?>.of(state.selectedIdByScope)
          ..[scopeId] = selected,
      ),
    );
  }

  /// Drops open ids that are no longer in [availableIds] (catalog changed).
  void pruneToAvailable(String scopeId, Iterable<String> availableIds) {
    final available = availableIds.toSet();
    final open = List<String>.of(state.openIdsByScope[scopeId] ?? const []);
    final nextOpen = [for (final id in open) if (available.contains(id)) id];
    if (nextOpen.length == open.length) {
      final selected = state.selectedIdByScope[scopeId];
      if (selected == null || available.contains(selected)) return;
    }
    String? selected = state.selectedIdByScope[scopeId];
    if (selected != null && !nextOpen.contains(selected)) {
      selected = nextOpen.isEmpty ? null : nextOpen.last;
    }
    emit(
      state.copyWith(
        openIdsByScope: Map<String, List<String>>.of(state.openIdsByScope)
          ..[scopeId] = nextOpen,
        selectedIdByScope: Map<String, String?>.of(state.selectedIdByScope)
          ..[scopeId] = selected,
      ),
    );
  }

  void removeWorkspace(String scopeId) {
    if (!state.openIdsByScope.containsKey(scopeId) &&
        !state.selectedIdByScope.containsKey(scopeId)) {
      return;
    }
    emit(
      state.copyWith(
        openIdsByScope: Map<String, List<String>>.of(state.openIdsByScope)
          ..remove(scopeId),
        selectedIdByScope: Map<String, String?>.of(state.selectedIdByScope)
          ..remove(scopeId),
      ),
    );
  }
}
