import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/llm_config.dart';
import '../repositories/app_settings_repository.dart';
import '../repositories/llm_config_repository.dart';
import '../services/llm_config_path_resolver.dart';
import '../utils/logger.dart';

class LlmConfigState extends Equatable {
  const LlmConfigState({
    this.config = const LlmConfig(),
    this.savedConfig = const LlmConfig(),
    this.isLoading = false,
    this.statusMessage = '',
    this.selectedProviderName,
    this.configPathOverride = '',
    this.effectiveConfigPath = '',
    this.pathSource = LlmConfigPathSource.defaultPath,
  });

  final LlmConfig config;
  final LlmConfig savedConfig;
  final bool isLoading;
  final String statusMessage;
  final String? selectedProviderName;

  /// Raw user-entered override (may contain ~). Empty means "use default".
  final String configPathOverride;

  /// Absolute, normalized path actually used by the repository.
  final String effectiveConfigPath;

  final LlmConfigPathSource pathSource;

  bool get isUsingCustomPath => pathSource == LlmConfigPathSource.userOverride;

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
    String? configPathOverride,
    String? effectiveConfigPath,
    LlmConfigPathSource? pathSource,
  }) {
    return LlmConfigState(
      config: config ?? this.config,
      savedConfig: savedConfig ?? this.savedConfig,
      isLoading: isLoading ?? this.isLoading,
      statusMessage: statusMessage ?? this.statusMessage,
      selectedProviderName: selectedProviderName ?? this.selectedProviderName,
      configPathOverride: configPathOverride ?? this.configPathOverride,
      effectiveConfigPath: effectiveConfigPath ?? this.effectiveConfigPath,
      pathSource: pathSource ?? this.pathSource,
    );
  }

  @override
  List<Object?> get props => [
        config,
        savedConfig,
        isLoading,
        statusMessage,
        selectedProviderName,
        configPathOverride,
        effectiveConfigPath,
        pathSource,
      ];
}

typedef LlmConfigRepositoryFactory = LlmConfigRepository Function(String path);

class LlmConfigCubit extends Cubit<LlmConfigState> {
  LlmConfigCubit({
    required AppSettingsRepository appSettings,
    required String currentDirectory,
    required String? homeDirectory,
    String Function()? executableResolver,
    LlmConfigRepositoryFactory? repositoryFactory,
    LlmConfig initialConfig = const LlmConfig(),
  })  : _appSettings = appSettings,
        _currentDirectory = currentDirectory,
        _homeDirectory = homeDirectory,
        _executableResolver = executableResolver ?? (() => ''),
        _repositoryFactory =
            repositoryFactory ?? ((path) => LlmConfigRepository(File(path))),
        super(LlmConfigState(
            config: initialConfig, savedConfig: initialConfig));

  final AppSettingsRepository _appSettings;
  final String _currentDirectory;
  final String? _homeDirectory;
  final String Function() _executableResolver;
  final LlmConfigRepositoryFactory _repositoryFactory;
  LlmConfigRepository? _repository;

  void selectProvider(String name) {
    if (state.selectedProviderName == name) return;
    emit(state.copyWith(selectedProviderName: name));
  }

  Future<void> load() async {
    appLogger.i('LlmConfigCubit loading...');
    emit(state.copyWith(isLoading: true));

    final override = await _appSettings.loadLlmConfigPathOverride();
    final resolved = resolveLlmConfigPath(
      userOverride: override,
      currentDirectory: _currentDirectory,
      homeDirectory: _homeDirectory,
      cliExecutablePath: _executableResolver(),
    );
    _repository = _repositoryFactory(resolved.path);

    final config = await _repository!.load();
    emit(state.copyWith(
      config: config,
      savedConfig: config,
      isLoading: false,
      statusMessage: 'Loaded LLM config.',
      configPathOverride: override ?? '',
      effectiveConfigPath: resolved.path,
      pathSource: resolved.source,
    ));
    appLogger.i(
        'LlmConfigCubit loaded ${config.providers.length} providers, ${config.models.length} models from ${resolved.path} (${resolved.source.name})');
  }

  /// Persist a new override and reload from the new path. Pass null or empty
  /// to clear the override and revert to the default path.
  Future<void> setConfigPath(String? rawOverride) async {
    final normalized = rawOverride?.trim();
    final toStore = (normalized == null || normalized.isEmpty) ? null : normalized;
    await _appSettings.saveLlmConfigPathOverride(toStore);
    await load();
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
