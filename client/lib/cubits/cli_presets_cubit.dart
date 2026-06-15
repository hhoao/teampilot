import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../models/cli_preset.dart';
import '../models/team_config.dart';
import '../repositories/cli_presets_repository.dart';
import '../utils/logger.dart';

enum CliPresetsLoadStatus { idle, loading, ready, error }

class CliPresetsState extends Equatable {
  const CliPresetsState({
    this.presets = const [],
    this.status = CliPresetsLoadStatus.idle,
    this.errorMessage,
  });

  final List<CliPreset> presets;
  final CliPresetsLoadStatus status;
  final String? errorMessage;

  CliPresetsState copyWith({
    List<CliPreset>? presets,
    CliPresetsLoadStatus? status,
    String? errorMessage,
    bool clearError = false,
  }) {
    return CliPresetsState(
      presets: presets ?? this.presets,
      status: status ?? this.status,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  CliPreset? presetById(String id) {
    for (final p in presets) {
      if (p.id == id) return p;
    }
    return null;
  }

  @override
  List<Object?> get props => [presets, status, errorMessage];
}

class CliPresetsCubit extends Cubit<CliPresetsState> {
  CliPresetsCubit({required CliPresetsRepository repository})
      : _repository = repository,
        super(const CliPresetsState());

  final CliPresetsRepository _repository;
  static const _uuid = Uuid();

  Future<void> load() async {
    if (state.status == CliPresetsLoadStatus.loading) return;
    emit(state.copyWith(status: CliPresetsLoadStatus.loading, clearError: true));
    try {
      final presets = await _repository.load();
      emit(state.copyWith(presets: presets, status: CliPresetsLoadStatus.ready));
    } on Object catch (e) {
      appLogger.e('[cli-presets] load failed: $e');
      emit(state.copyWith(
        status: CliPresetsLoadStatus.error,
        errorMessage: e.toString(),
      ));
    }
  }

  Future<void> addPreset({
    required String name,
    required CliTool cli,
    required String provider,
    required String model,
    String effort = '',
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final preset = CliPreset(
      id: _uuid.v4(),
      name: trimmedName,
      cli: cli,
      provider: provider.trim(),
      model: model.trim(),
      effort: effort.trim(),
      createdAt: now,
      updatedAt: now,
    );

    final next = List<CliPreset>.from(state.presets)..add(preset);
    await _persist(next);
  }

  Future<void> updatePreset({
    required String id,
    required String name,
    required CliTool cli,
    required String provider,
    required String model,
    String effort = '',
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) return;

    final index = state.presets.indexWhere((p) => p.id == id);
    if (index < 0) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final next = List<CliPreset>.from(state.presets);
    next[index] = next[index].copyWith(
      name: trimmedName,
      cli: cli,
      provider: provider.trim(),
      model: model.trim(),
      effort: effort.trim(),
      updatedAt: now,
    );

    await _persist(next);
  }

  Future<void> deletePreset(String id) async {
    final next = state.presets.where((p) => p.id != id).toList(growable: false);
    if (next.length == state.presets.length) return; // nothing removed
    await _persist(next);
  }

  Future<void> _persist(List<CliPreset> presets) async {
    final saved = await _repository.save(presets);
    emit(state.copyWith(presets: saved));
  }
}
