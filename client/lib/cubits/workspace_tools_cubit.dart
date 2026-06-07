import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Per-project right-tools UI state (which tool tab is selected). Keyed by
/// `projectId` so each open project remembers its own selection across project
/// switches. Panel width/visibility stay global in [LayoutCubit] — this cubit
/// only owns the selected-tool index.
class WorkspaceToolsState extends Equatable {
  const WorkspaceToolsState({this.selectedByProject = const {}});

  final Map<String, int> selectedByProject;

  WorkspaceToolsState copyWith({Map<String, int>? selectedByProject}) =>
      WorkspaceToolsState(
        selectedByProject: selectedByProject ?? this.selectedByProject,
      );

  @override
  List<Object?> get props => [selectedByProject];
}

class WorkspaceToolsCubit extends Cubit<WorkspaceToolsState> {
  WorkspaceToolsCubit() : super(const WorkspaceToolsState());

  int selectedIndexFor(String projectId) =>
      state.selectedByProject[projectId] ?? 0;

  void setSelectedIndex(String projectId, int index) {
    if (selectedIndexFor(projectId) == index) return;
    final next = Map<String, int>.of(state.selectedByProject)
      ..[projectId] = index;
    emit(state.copyWith(selectedByProject: next));
  }

  void removeProject(String projectId) {
    if (!state.selectedByProject.containsKey(projectId)) return;
    final next = Map<String, int>.of(state.selectedByProject)
      ..remove(projectId);
    emit(state.copyWith(selectedByProject: next));
  }
}
