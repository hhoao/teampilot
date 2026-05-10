import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/llm_config.dart';
import '../repositories/llm_config_repository.dart';
import '../utils/logger.dart';

class LlmConfigState extends Equatable {
  const LlmConfigState({
    this.config = const LlmConfig(),
    this.savedConfig = const LlmConfig(),
    this.isLoading = false,
    this.statusMessage = '',
    this.selectedProviderName,
    this.filePath = 'flashshkyai/llm/llm_config.json',
  });

  final LlmConfig config;
  final LlmConfig savedConfig;
  final bool isLoading;
  final String statusMessage;
  final String? selectedProviderName;
  final String filePath;

  String? get effectiveProviderName {
    if (selectedProviderName != null &&
        config.providers.containsKey(selectedProviderName)) {
      return selectedProviderName;
    }
    return config.providers.keys.firstOrNull;
  }

  LlmConfigState copyWith({
    LlmConfig? config,
    LlmConfig? savedConfig,
    bool? isLoading,
    String? statusMessage,
    String? selectedProviderName,
    String? filePath,
  }) {
    return LlmConfigState(
      config: config ?? this.config,
      savedConfig: savedConfig ?? this.savedConfig,
      isLoading: isLoading ?? this.isLoading,
      statusMessage: statusMessage ?? this.statusMessage,
      selectedProviderName:
          selectedProviderName ?? this.selectedProviderName,
      filePath: filePath ?? this.filePath,
    );
  }

  @override
  List<Object?> get props =>
      [config, savedConfig, isLoading, statusMessage, selectedProviderName, filePath];
}

class LlmConfigCubit extends Cubit<LlmConfigState> {
  LlmConfigCubit({
    LlmConfigRepository? repository,
    LlmConfig initialConfig = const LlmConfig(),
  })  : _repository = repository,
        super(LlmConfigState(
            config: initialConfig, savedConfig: initialConfig));

  final LlmConfigRepository? _repository;

  void selectProvider(String name) {
    if (state.selectedProviderName == name) return;
    emit(state.copyWith(selectedProviderName: name));
  }

  Future<void> load() async {
    appLogger.i('LlmConfigCubit loading...');
    emit(state.copyWith(isLoading: true));
    final config = await _repository?.load() ?? const LlmConfig();
    emit(state.copyWith(
        config: config,
        savedConfig: config,
        isLoading: false,
        statusMessage: 'Loaded LLM config.'));
    appLogger.i(
        'LlmConfigCubit loaded ${config.providers.length} providers, ${config.models.length} models');
  }

  Future<void> save() async {
    await _repository?.save(state.config, previous: state.savedConfig);
    emit(state.copyWith(
        savedConfig: state.config, statusMessage: 'Saved LLM config.'));
  }

  void addProvider(LlmProviderConfig provider) {
    final config = state.config.copyWith(
        providers: {...state.config.providers, provider.name: provider});
    emit(state.copyWith(
        config: config, statusMessage: 'Added provider ${provider.name}.'));
  }

  void updateProvider(String name, LlmProviderConfig provider) {
    final updated =
        Map<String, LlmProviderConfig>.from(state.config.providers);
    updated[name] = provider;
    emit(state.copyWith(
        config: state.config.copyWith(providers: updated),
        statusMessage: 'Updated provider $name.'));
  }

  void deleteProvider(String name) {
    final updated =
        Map<String, LlmProviderConfig>.from(state.config.providers);
    updated.remove(name);
    final newSelected = state.selectedProviderName == name
        ? updated.keys.firstOrNull
        : state.selectedProviderName;
    emit(state.copyWith(
        config: state.config.copyWith(providers: updated),
        selectedProviderName: newSelected,
        statusMessage: 'Deleted provider $name.'));
  }

  void addModel(LlmModelConfig model) {
    emit(state.copyWith(
        config: state.config.copyWith(
            models: {...state.config.models, model.id: model}),
        statusMessage: 'Added model ${model.name}.'));
  }

  void updateModel(String id, LlmModelConfig model) {
    final updated =
        Map<String, LlmModelConfig>.from(state.config.models);
    updated[id] = model;
    emit(state.copyWith(
        config: state.config.copyWith(models: updated),
        statusMessage: 'Updated model ${model.name}.'));
  }

  void deleteModel(String id) {
    final updated =
        Map<String, LlmModelConfig>.from(state.config.models);
    updated.remove(id);
    emit(state.copyWith(
        config: state.config.copyWith(models: updated),
        statusMessage: 'Deleted model $id.'));
  }

  String revealApiKey(String providerName) {
    return state.savedConfig.providers[providerName]?.apiKey ?? '';
  }
}
