import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/app_provider_config.dart';
import '../models/llm_config.dart';
import '../repositories/app_provider_repository.dart';
import '../services/app_storage.dart';
import '../services/tool_config_generator.dart';

class AppProviderState extends Equatable {
  const AppProviderState({
    this.selectedCli = AppProviderCli.claude,
    this.providersByCli = const {},
    this.selectedProviderIdByCli = const {},
    this.isLoading = false,
    this.statusMessage = '',
  });

  final AppProviderCli selectedCli;
  final Map<AppProviderCli, List<AppProviderConfig>> providersByCli;
  final Map<AppProviderCli, String?> selectedProviderIdByCli;
  final bool isLoading;
  final String statusMessage;

  List<AppProviderConfig> get providers =>
      providersByCli[selectedCli] ?? const [];

  List<AppProviderConfig> providersFor(AppProviderCli cli) =>
      providersByCli[cli] ?? const [];

  String? get selectedId => selectedProviderIdByCli[selectedCli];

  AppProviderConfig? get selectedProvider {
    final id = selectedId;
    if (id == null) return null;
    for (final p in providers) {
      if (p.id == id) return p;
    }
    return null;
  }

  AppProviderState copyWith({
    AppProviderCli? selectedCli,
    Map<AppProviderCli, List<AppProviderConfig>>? providersByCli,
    Map<AppProviderCli, String?>? selectedProviderIdByCli,
    bool? isLoading,
    String? statusMessage,
  }) {
    return AppProviderState(
      selectedCli: selectedCli ?? this.selectedCli,
      providersByCli: providersByCli ?? this.providersByCli,
      selectedProviderIdByCli:
          selectedProviderIdByCli ?? this.selectedProviderIdByCli,
      isLoading: isLoading ?? this.isLoading,
      statusMessage: statusMessage ?? this.statusMessage,
    );
  }

  @override
  List<Object?> get props => [
    selectedCli,
    providersByCli,
    selectedProviderIdByCli,
    isLoading,
    statusMessage,
  ];
}

class AppProviderCubit extends Cubit<AppProviderState> {
  AppProviderCubit({
    AppProviderRepository? repository,
    ToolConfigGenerator? generator,
  }) : _repository = repository ?? AppProviderRepository(),
       _generator = generator ?? const ToolConfigGenerator(),
       super(const AppProviderState());

  final AppProviderRepository _repository;
  final ToolConfigGenerator _generator;

  String get catalogPath => AppPathsBootstrapper.current.providerConfigDir;

  Future<void> load() async {
    emit(state.copyWith(isLoading: true, statusMessage: ''));
    final byCli = <AppProviderCli, List<AppProviderConfig>>{};
    final selectedByCli = Map<AppProviderCli, String?>.from(
      state.selectedProviderIdByCli,
    );
    for (final cli in AppProviderCli.values) {
      final providers = await _repository.loadProviders(cli);
      byCli[cli] = providers;
      final selected = selectedByCli[cli];
      selectedByCli[cli] =
          selected != null && providers.any((p) => p.id == selected)
          ? selected
          : providers.firstOrNull?.id;
    }
    emit(
      state.copyWith(
        providersByCli: byCli,
        selectedProviderIdByCli: selectedByCli,
        isLoading: false,
        statusMessage: (byCli[state.selectedCli] ?? const []).isEmpty
            ? 'No providers yet.'
            : 'Ready.',
      ),
    );
  }

  Future<void> setSelectedCli(AppProviderCli cli) async {
    if (cli == state.selectedCli && state.providersByCli.containsKey(cli)) {
      return;
    }
    var byCli = state.providersByCli;
    var selectedByCli = state.selectedProviderIdByCli;
    if (!byCli.containsKey(cli)) {
      final providers = await _repository.loadProviders(cli);
      byCli = {...byCli, cli: providers};
      selectedByCli = {
        ...selectedByCli,
        cli:
            selectedByCli[cli] != null &&
                providers.any((p) => p.id == selectedByCli[cli])
            ? selectedByCli[cli]
            : providers.firstOrNull?.id,
      };
    }
    emit(
      state.copyWith(
        selectedCli: cli,
        providersByCli: byCli,
        selectedProviderIdByCli: selectedByCli,
      ),
    );
  }

  void selectProvider(String id) {
    if (!state.providers.any((p) => p.id == id)) return;
    emit(
      state.copyWith(
        selectedProviderIdByCli: {
          ...state.selectedProviderIdByCli,
          state.selectedCli: id,
        },
      ),
    );
  }

  Future<bool> upsertProvider(AppProviderConfig provider) async {
    final cli = provider.cli;
    final trimmedId = provider.id.trim();
    if (trimmedId.isEmpty) return false;
    final current =
        state.providersByCli[cli] ?? await _repository.loadProviders(cli);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final existing = current.where((p) => p.id == trimmedId).firstOrNull;
    final normalizedConfig = _normalizedConfigForCli(
      cli: cli,
      providerId: trimmedId,
      config: provider.config,
    );
    final next = provider.copyWith(
      id: trimmedId,
      cli: cli,
      name: provider.name.trim(),
      config: normalizedConfig,
      createdAt:
          existing?.createdAt ??
          (provider.createdAt > 0 ? provider.createdAt : now),
      updatedAt: now,
    );
    final list = [
      for (final p in current)
        if (p.id != trimmedId) p,
      next,
    ]..sort((a, b) => a.name.compareTo(b.name));
    await _repository.saveProviders(cli, list);
    emit(
      state.copyWith(
        selectedCli: cli,
        providersByCli: {...state.providersByCli, cli: list},
        selectedProviderIdByCli: {
          ...state.selectedProviderIdByCli,
          cli: trimmedId,
        },
        statusMessage: 'Saved ${next.name}.',
      ),
    );
    return true;
  }

  Future<void> deleteProvider(String id) async {
    final cli = state.selectedCli;
    final list = state.providers
        .where((p) => p.id != id)
        .toList(growable: false);
    await _repository.saveProviders(cli, list);
    final selectedStillExists = list.any((p) => p.id == state.selectedId);
    final nextSelected = selectedStillExists
        ? state.selectedId
        : list.firstOrNull?.id;
    emit(
      state.copyWith(
        providersByCli: {...state.providersByCli, cli: list},
        selectedProviderIdByCli: {
          ...state.selectedProviderIdByCli,
          cli: nextSelected,
        },
        statusMessage: 'Provider removed.',
      ),
    );
  }

  LlmConfig flashskyaiLlmConfigFor(AppProviderConfig provider) {
    return _generator.buildFlashskyaiLlmConfig(provider);
  }

  Future<void> updateFlashskyaiModels(
    String providerId,
    Map<String, LlmModelConfig> models,
  ) async {
    final provider = state
        .providersFor(AppProviderCli.flashskyai)
        .where((p) => p.id == providerId)
        .firstOrNull;
    if (provider == null) return;
    final modelsJson = {
      for (final entry in models.entries) entry.key: entry.value.toJson(),
    };
    final updated = provider.copyWith(
      config: {...provider.config, 'models': modelsJson},
    );
    await upsertProvider(updated);
  }

  static String slugifyId(String name) {
    final slug = name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return slug.isEmpty ? 'provider' : slug;
  }

  static String uniqueId(String base, Iterable<String> existing) {
    var candidate = base;
    var i = 2;
    while (existing.contains(candidate)) {
      candidate = '$base-$i';
      i++;
    }
    return candidate;
  }

  Map<String, Object?> _normalizedConfigForCli({
    required AppProviderCli cli,
    required String providerId,
    required Map<String, Object?> config,
  }) {
    if (cli != AppProviderCli.flashskyai) return config;
    return _normalizeFlashskyaiModelsProvider(
      config: config,
      providerId: providerId,
    );
  }

  Map<String, Object?> _normalizeFlashskyaiModelsProvider({
    required Map<String, Object?> config,
    required String providerId,
  }) {
    final rawModels = config['models'];
    if (rawModels is! Map) return config;
    final normalizedModels = <String, Object?>{};
    for (final entry in rawModels.entries) {
      final key = entry.key.toString();
      final value = entry.value;
      if (value is Map) {
        final modelJson = Map<String, Object?>.from(value);
        modelJson['provider'] = providerId;
        normalizedModels[key] = modelJson;
      } else {
        normalizedModels[key] = value;
      }
    }
    return {
      ...config,
      'models': normalizedModels,
    };
  }
}
