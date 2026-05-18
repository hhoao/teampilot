import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/llm_config.dart';
import '../models/ssh_profile.dart';
import '../repositories/app_settings_repository.dart';
import '../repositories/llm_config_store.dart';
import '../services/llm_config_path_resolver.dart';
import '../services/remote_file_store.dart';
import '../services/remote_home_resolver.dart';
import '../services/ssh_client_factory.dart';
import '../services/wsl_posix_path_for_windows_io.dart';
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
    this.storageIsRemote = false,
  });

  final LlmConfig config;
  final LlmConfig savedConfig;
  final bool isLoading;
  final String statusMessage;
  final String? selectedProviderName;

  /// Raw user-entered override (may contain ~). Empty means "use default".
  final String configPathOverride;

  /// Absolute, normalized path used by the active store (local or remote).
  final String effectiveConfigPath;

  final LlmConfigPathSource pathSource;

  /// True when [effectiveConfigPath] is read/written over SSH (SFTP).
  final bool storageIsRemote;

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
    bool? storageIsRemote,
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
      storageIsRemote: storageIsRemote ?? this.storageIsRemote,
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
        storageIsRemote,
      ];
}

typedef LlmConfigStoreFactory = LlmConfigStore Function(String path);

class LlmConfigCubit extends Cubit<LlmConfigState> {
  LlmConfigCubit({
    required AppSettingsRepository appSettings,
    required String currentDirectory,
    required String? homeDirectory,
    String Function()? executableResolver,
    LlmConfigStoreFactory? storeFactory,
    bool Function()? isSshMode,
    SshProfile? Function()? sshProfileResolver,
    SshClientFactory? sshClientFactory,
    String Function()? sshWorkingDirectoryResolver,
    RemoteHomeResolver? remoteHomeResolver,
    LlmConfig initialConfig = const LlmConfig(),
  })  : _appSettings = appSettings,
        _currentDirectory = currentDirectory,
        _homeDirectory = homeDirectory,
        _executableResolver = executableResolver ?? (() => ''),
        _localStoreFactory = storeFactory ?? ((path) => LocalLlmConfigStore(path)),
        _isSshMode = isSshMode,
        _sshProfileResolver = sshProfileResolver,
        _sshClientFactory = sshClientFactory,
        _sshWorkingDirectoryResolver = sshWorkingDirectoryResolver,
        _remoteHomeResolver = remoteHomeResolver,
        super(LlmConfigState(config: initialConfig, savedConfig: initialConfig));

  final AppSettingsRepository _appSettings;
  final String _currentDirectory;
  final String? _homeDirectory;
  final String Function() _executableResolver;
  final LlmConfigStoreFactory _localStoreFactory;
  final bool Function()? _isSshMode;
  final SshProfile? Function()? _sshProfileResolver;
  final SshClientFactory? _sshClientFactory;
  final String Function()? _sshWorkingDirectoryResolver;
  final RemoteHomeResolver? _remoteHomeResolver;
  LlmConfigStore? _store;

  void selectProvider(String name) {
    if (state.selectedProviderName == name) return;
    emit(state.copyWith(selectedProviderName: name));
  }

  Future<void> load() async {
    appLogger.i('LlmConfigCubit loading...');
    emit(state.copyWith(isLoading: true));

    final override = await _appSettings.loadLlmConfigPathOverride();
    final sshActive = _isSshMode?.call() ?? false;
    final profile = sshActive ? _sshProfileResolver?.call() : null;
    final useRemote =
        sshActive && profile != null && _sshClientFactory != null;

    var homeDirectory = _homeDirectory;
    var currentDirectory = _currentDirectory;
    if (useRemote) {
      final factory = _sshClientFactory;
      final remoteHome = await (_remoteHomeResolver ??
              RemoteHomeResolver(clientFactory: factory))
          .resolve(profile);
      if (remoteHome != null && remoteHome.isNotEmpty) {
        homeDirectory = remoteHome;
      }
      final workdir = _sshWorkingDirectoryResolver?.call().trim() ?? '';
      currentDirectory = workdir.isNotEmpty
          ? workdir
          : (homeDirectory?.trim().isNotEmpty == true ? homeDirectory! : '/');
    }

    final resolved = resolveLlmConfigPath(
      userOverride: override,
      currentDirectory: currentDirectory,
      homeDirectory: homeDirectory,
      cliExecutablePath: _executableResolver(),
      usePosixPaths: useRemote,
    );

    final effectivePath = useRemote
        ? resolved.path
        : await windowsFilePathForPossibleWslPosixPath(resolved.path);

    if (useRemote) {
      final factory = _sshClientFactory;
      _store = RemoteLlmConfigStore(
        remotePath: effectivePath,
        fileStore: RemoteFileStore(
          profile: profile,
          clientFactory: factory,
        ),
      );
    } else {
      _store = _localStoreFactory(effectivePath);
    }

    final config = await _store!.load();
    emit(state.copyWith(
      config: config,
      savedConfig: config,
      isLoading: false,
      statusMessage: 'Loaded LLM config.',
      configPathOverride: override ?? '',
      effectiveConfigPath: effectivePath,
      pathSource: resolved.source,
      storageIsRemote: useRemote,
    ));
    appLogger.i(
      'LlmConfigCubit loaded ${config.providers.length} providers, '
      '${config.models.length} models from $effectivePath '
      '(${resolved.source.name}, remote=$useRemote)',
    );
  }

  /// Persist a new override and reload from the new path. Pass null or empty
  /// to clear the override and revert to the default path.
  Future<void> setConfigPath(String? rawOverride) async {
    final normalized = rawOverride?.trim();
    final toStore =
        (normalized == null || normalized.isEmpty) ? null : normalized;
    await _appSettings.saveLlmConfigPathOverride(toStore);
    await load();
  }

  Future<void> save() async {
    final previous = state.savedConfig;
    final current = state.config;
    await _store?.save(current, previous: previous);
    if (isClosed) return;
    emit(state.copyWith(
      savedConfig: current,
      statusMessage: 'Saved LLM config.',
    ));
  }

  Future<void> _persistConfigChange({
    required LlmConfig newConfig,
    required String statusMessage,
    String? selectedProviderName,
    bool updateSelectedProvider = false,
  }) async {
    final previous = state.savedConfig;
    await _store?.save(newConfig, previous: previous);
    if (isClosed) return;
    final nextSelection = updateSelectedProvider
        ? selectedProviderName
        : state.selectedProviderName;
    emit(LlmConfigState(
      config: newConfig,
      savedConfig: newConfig,
      isLoading: state.isLoading,
      statusMessage: statusMessage,
      selectedProviderName: nextSelection,
      configPathOverride: state.configPathOverride,
      effectiveConfigPath: state.effectiveConfigPath,
      pathSource: state.pathSource,
      storageIsRemote: state.storageIsRemote,
    ));
  }

  void addProvider(LlmProviderConfig provider) {
    final newConfig = state.config.copyWith(
      providers: {...state.config.providers, provider.name: provider},
    );
    unawaited(_persistConfigChange(
      newConfig: newConfig,
      statusMessage: 'Added provider ${provider.name}.',
    ));
  }

  void updateProvider(String name, LlmProviderConfig provider) {
    final updated = Map<String, LlmProviderConfig>.from(state.config.providers);
    updated[name] = provider;
    unawaited(_persistConfigChange(
      newConfig: state.config.copyWith(providers: updated),
      statusMessage: 'Updated provider $name.',
    ));
  }

  /// Renames a provider key and updates models that reference it.
  /// Returns false when [to] is empty, unchanged, or already taken.
  bool renameProvider(String from, String to) {
    final trimmed = to.trim();
    if (trimmed.isEmpty) {
      emit(state.copyWith(statusMessage: 'Provider name is required.'));
      return false;
    }
    if (trimmed == from) return true;
    if (!state.config.providers.containsKey(from)) {
      emit(state.copyWith(statusMessage: 'Provider $from not found.'));
      return false;
    }
    if (state.config.providers.containsKey(trimmed)) {
      emit(
        state.copyWith(statusMessage: 'Provider "$trimmed" already exists.'),
      );
      return false;
    }

    final old = state.config.providers[from]!;
    final providers = Map<String, LlmProviderConfig>.from(state.config.providers)
      ..remove(from)
      ..[trimmed] = old.copyWith(name: trimmed);

    final models = <String, LlmModelConfig>{};
    for (final entry in state.config.models.entries) {
      final model = entry.value;
      models[entry.key] = model.provider == from
          ? model.copyWith(provider: trimmed)
          : model;
    }

    final newSelected =
        state.selectedProviderName == from ? trimmed : state.selectedProviderName;
    unawaited(
      _persistConfigChange(
        newConfig: state.config.copyWith(providers: providers, models: models),
        statusMessage: 'Renamed provider $from to $trimmed.',
        selectedProviderName: newSelected,
        updateSelectedProvider: true,
      ),
    );
    return true;
  }

  void deleteProvider(String name) {
    final updated = Map<String, LlmProviderConfig>.from(state.config.providers);
    updated.remove(name);
    final newSelected = state.selectedProviderName == name
        ? updated.keys.firstOrNull
        : state.selectedProviderName;
    unawaited(_persistConfigChange(
      newConfig: state.config.copyWith(providers: updated),
      statusMessage: 'Deleted provider $name.',
      selectedProviderName: newSelected,
      updateSelectedProvider: true,
    ));
  }

  void addModel(LlmModelConfig model) {
    unawaited(_persistConfigChange(
      newConfig: state.config.copyWith(
        models: {...state.config.models, model.id: model},
      ),
      statusMessage: 'Added model ${model.name}.',
    ));
  }

  void updateModel(String id, LlmModelConfig model) {
    final updated = Map<String, LlmModelConfig>.from(state.config.models);
    updated[id] = model;
    unawaited(_persistConfigChange(
      newConfig: state.config.copyWith(models: updated),
      statusMessage: 'Updated model ${model.name}.',
    ));
  }

  void deleteModel(String id) {
    final updated = Map<String, LlmModelConfig>.from(state.config.models);
    updated.remove(id);
    unawaited(_persistConfigChange(
      newConfig: state.config.copyWith(models: updated),
      statusMessage: 'Deleted model $id.',
    ));
  }

  String revealApiKey(String providerName) {
    return state.savedConfig.providers[providerName]?.apiKey ?? '';
  }
}
