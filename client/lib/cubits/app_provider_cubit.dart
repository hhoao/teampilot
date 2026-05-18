import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/app_provider_config.dart';
import '../models/llm_config.dart';
import '../repositories/app_provider_repository.dart';
import '../services/app_storage.dart';
import '../services/tool_config_generator.dart';

class AppProviderState extends Equatable {
  const AppProviderState({
    this.providers = const [],
    this.selectedId,
    this.isLoading = false,
    this.statusMessage = '',
  });

  final List<AppProviderConfig> providers;
  final String? selectedId;
  final bool isLoading;
  final String statusMessage;

  AppProviderConfig? get selectedProvider {
    final id = selectedId;
    if (id == null) return null;
    for (final p in providers) {
      if (p.id == id) return p;
    }
    return null;
  }

  AppProviderState copyWith({
    List<AppProviderConfig>? providers,
    String? selectedId,
    bool? isLoading,
    String? statusMessage,
    bool clearSelectedId = false,
  }) {
    return AppProviderState(
      providers: providers ?? this.providers,
      selectedId: clearSelectedId ? null : (selectedId ?? this.selectedId),
      isLoading: isLoading ?? this.isLoading,
      statusMessage: statusMessage ?? this.statusMessage,
    );
  }

  @override
  List<Object?> get props => [providers, selectedId, isLoading, statusMessage];
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

  String get catalogPath => AppStorage.providerConfigFile;

  Future<void> load() async {
    emit(state.copyWith(isLoading: true, statusMessage: ''));
    final providers = await _repository.loadProviders();
    final selected = state.selectedId;
    final nextSelected =
        selected != null && providers.any((p) => p.id == selected)
        ? selected
        : providers.firstOrNull?.id;
    emit(
      state.copyWith(
        providers: providers,
        selectedId: nextSelected,
        isLoading: false,
        statusMessage: providers.isEmpty ? 'No providers yet.' : 'Ready.',
      ),
    );
  }

  void selectProvider(String id) {
    if (!state.providers.any((p) => p.id == id)) return;
    emit(state.copyWith(selectedId: id));
  }

  Future<bool> upsertProvider(AppProviderConfig provider) async {
    final trimmedId = provider.id.trim();
    if (trimmedId.isEmpty) return false;
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final existing = state.providers
        .where((p) => p.id == trimmedId)
        .firstOrNull;
    final next = provider.copyWith(
      id: trimmedId,
      createdAt:
          existing?.createdAt ??
          (provider.createdAt > 0 ? provider.createdAt : now),
      updatedAt: now,
    );
    final list = [
      for (final p in state.providers)
        if (p.id != trimmedId) p,
      next,
    ]..sort((a, b) => a.name.compareTo(b.name));
    await _repository.saveProviders(list);
    emit(
      state.copyWith(
        providers: list,
        selectedId: trimmedId,
        statusMessage: 'Saved ${next.name}.',
      ),
    );
    return true;
  }

  Future<void> deleteProvider(String id) async {
    final list = state.providers
        .where((p) => p.id != id)
        .toList(growable: false);
    await _repository.saveProviders(list);
    final selectedStillExists = list.any((p) => p.id == state.selectedId);
    final nextSelected = selectedStillExists
        ? state.selectedId
        : list.firstOrNull?.id;
    emit(
      state.copyWith(
        providers: list,
        clearSelectedId: nextSelected == null,
        selectedId: nextSelected,
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
    final provider = state.providers
        .where((p) => p.id == providerId)
        .firstOrNull;
    if (provider == null) return;
    final modelsJson = {
      for (final entry in models.entries) entry.key: entry.value.toJson(),
    };
    final tool = provider.toolConfigs.flashskyai.unknownFields;
    final updated = provider.copyWith(
      toolConfigs: provider.toolConfigs.copyWith(
        flashskyai: AppProviderToolConfigPayload(
          unknownFields: {...tool, 'models': modelsJson},
        ),
      ),
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
}
