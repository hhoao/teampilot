import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/config_bundle.dart';
import '../models/workspace_project_config.dart';
import '../repositories/workspace_project_config_repository.dart';

class WorkspaceProjectConfigState {
  const WorkspaceProjectConfigState({
    this.loading = false,
    this.config = const WorkspaceProjectConfig(),
    this.error,
  });

  final bool loading;
  final WorkspaceProjectConfig config;
  final String? error;

  WorkspaceProjectConfigState copyWith({
    bool? loading,
    WorkspaceProjectConfig? config,
    String? error,
    bool clearError = false,
  }) {
    return WorkspaceProjectConfigState(
      loading: loading ?? this.loading,
      config: config ?? this.config,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class WorkspaceProjectConfigCubit extends Cubit<WorkspaceProjectConfigState> {
  WorkspaceProjectConfigCubit({
    required WorkspaceProjectConfigRepository repository,
    required this.workspaceId,
  }) : _repository = repository,
       super(const WorkspaceProjectConfigState()) {
    _live.putIfAbsent(workspaceId, () => {}).add(this);
  }

  static final _live = <String, Set<WorkspaceProjectConfigCubit>>{};

  final WorkspaceProjectConfigRepository _repository;
  final String workspaceId;

  /// Reloads every open manage-panel cubit for [workspaceId] (catalog MCP bus).
  static Future<void> reloadLive(String workspaceId) async {
    final cubits = List<WorkspaceProjectConfigCubit>.of(
      _live[workspaceId] ?? const {},
    );
    for (final cubit in cubits) {
      await cubit.load();
    }
  }

  @override
  Future<void> close() {
    final set = _live[workspaceId];
    set?.remove(this);
    if (set != null && set.isEmpty) {
      _live.remove(workspaceId);
    }
    return super.close();
  }

  Future<void> load() async {
    emit(state.copyWith(loading: true, clearError: true));
    try {
      final config = await _repository.load(workspaceId);
      emit(state.copyWith(loading: false, config: config));
    } on Object catch (error) {
      emit(state.copyWith(loading: false, error: error.toString()));
    }
  }

  Future<void> updateBundle(ConfigBundle bundle) async {
    final next = await _repository.updateBundle(
      workspaceId,
      (current) => current.copyWith(bundle: bundle),
    );
    emit(state.copyWith(config: next));
  }

  Future<void> setExtensionOverride(String extensionId, bool? value) async {
    final id = extensionId.trim();
    if (id.isEmpty) return;
    final next = await _repository.updateBundle(workspaceId, (current) {
      final overrides = Map<String, bool>.from(current.extensionOverrides);
      if (value == null) {
        overrides.remove(id);
      } else {
        overrides[id] = value;
      }
      return current.copyWith(extensionOverrides: Map.unmodifiable(overrides));
    });
    emit(state.copyWith(config: next));
  }
}
