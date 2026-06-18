import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Per-workspace right-tools UI state (which tool tab is selected). Keyed by
/// `workspaceId` so each open workspace remembers its own selection across workspace
/// switches. Panel width/visibility stay global in [LayoutCubit] — this cubit
/// only owns the selected-tool index.
class WorkspaceToolsState extends Equatable {
  const WorkspaceToolsState({this.selectedByWorkspace = const {}});

  final Map<String, int> selectedByWorkspace;

  WorkspaceToolsState copyWith({Map<String, int>? selectedByWorkspace}) =>
      WorkspaceToolsState(
        selectedByWorkspace: selectedByWorkspace ?? this.selectedByWorkspace,
      );

  @override
  List<Object?> get props => [selectedByWorkspace];
}

class WorkspaceToolsCubit extends Cubit<WorkspaceToolsState> {
  WorkspaceToolsCubit() : super(const WorkspaceToolsState());

  int selectedIndexFor(String workspaceId) =>
      state.selectedByWorkspace[workspaceId] ?? 0;

  void setSelectedIndex(String workspaceId, int index) {
    if (selectedIndexFor(workspaceId) == index) return;
    final next = Map<String, int>.of(state.selectedByWorkspace)
      ..[workspaceId] = index;
    emit(state.copyWith(selectedByWorkspace: next));
  }

  void removeWorkspace(String workspaceId) {
    if (!state.selectedByWorkspace.containsKey(workspaceId)) return;
    final next = Map<String, int>.of(state.selectedByWorkspace)
      ..remove(workspaceId);
    emit(state.copyWith(selectedByWorkspace: next));
  }
}
