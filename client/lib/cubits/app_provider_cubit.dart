import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/app_provider_config.dart';
import '../models/claude_credential_link_result.dart';
import '../models/llm_config.dart';
import '../repositories/app_provider_repository.dart';
import '../services/app_storage.dart';
import '../services/claude_provider_credentials_service.dart';
import '../services/provider_import_service.dart';
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
    ProviderImportService? importService,
    String? Function()? flashskyaiExecutablePath,
    ToolConfigGenerator? generator,
    ClaudeProviderCredentialsService? claudeCredentialsService,
    String? basePath,
  }) : _repository = repository ?? AppProviderRepository(basePath: basePath),
       _generator = generator ?? const ToolConfigGenerator(),
       _flashskyaiExecutablePath = flashskyaiExecutablePath,
       _importService = importService,
       _claudeCredentials =
           claudeCredentialsService ??
           ClaudeProviderCredentialsService(
             fs: AppStorage.fs,
             basePath: _resolveBasePath(basePath),
           ),
       super(const AppProviderState());

  final AppProviderRepository _repository;
  final ToolConfigGenerator _generator;
  final ProviderImportService? _importService;
  final String? Function()? _flashskyaiExecutablePath;
  final ClaudeProviderCredentialsService _claudeCredentials;

  static String _resolveBasePath(String? basePath) {
    if (basePath != null && basePath.trim().isNotEmpty) {
      return basePath.trim();
    }
    try {
      return AppStorage.paths.basePath;
    } on Object {
      return '';
    }
  }

  ProviderImportService _importServiceForRequest() {
    return _importService ??
        ProviderImportService(
          repository: _repository,
          flashskyaiExecutablePath: _flashskyaiExecutablePath?.call(),
        );
  }

  String get catalogPath => AppStorage.paths.providerConfigDir;

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

  Future<CredentialProbe> probeClaudeCredentials(String providerId) async {
    return _claudeCredentials.probe(providerId);
  }

  Future<bool> loginClaudeOfficialProvider(String providerId) async {
    final ok = await _claudeCredentials.runAuthLogin(providerId);
    if (!ok) return false;
    return _refreshClaudeCredentialStatus(providerId);
  }

  Future<bool> importClaudeCredentialsFromGlobal(
    String providerId, {
    bool replace = false,
  }) async {
    final home = AppStorage.home;
    final ok = await _claudeCredentials.importFromGlobal(
      providerId,
      homeDirectory: home,
      replace: replace,
    );
    if (!ok) return false;
    return _refreshClaudeCredentialStatus(providerId);
  }

  Future<bool> importClaudeCredentialsFromFile(
    String providerId,
    String path, {
    bool replace = false,
  }) async {
    final ok = await _claudeCredentials.importFromFile(
      providerId,
      path,
      replace: replace,
    );
    if (!ok) return false;
    return _refreshClaudeCredentialStatus(providerId);
  }

  Future<bool> revokeClaudeOfficialProvider(String providerId) async {
    final ok = await _claudeCredentials.revokeCredentials(providerId);
    if (!ok) return false;
    return _refreshClaudeCredentialStatus(providerId);
  }

  Future<bool> _refreshClaudeCredentialStatus(String providerId) async {
    final probe = await _claudeCredentials.probe(providerId);
    final provider = state.providers
        .where((p) => p.id == providerId)
        .firstOrNull;
    if (provider == null) return false;
    return upsertProvider(provider.withCredentialProbe(probe));
  }

  Future<ProviderImportResult> importFromExternal() async {
    final cli = state.selectedCli;
    emit(state.copyWith(isLoading: true, statusMessage: ''));
    final result = await _importServiceForRequest().importForCli(cli, onlyIfEmpty: false);

    final byCli = <AppProviderCli, List<AppProviderConfig>>{};
    final selectedByCli = Map<AppProviderCli, String?>.from(
      state.selectedProviderIdByCli,
    );
    for (final item in AppProviderCli.values) {
      final providers = await _repository.loadProviders(item);
      byCli[item] = providers;
      final selected = selectedByCli[item];
      selectedByCli[item] =
          selected != null && providers.any((p) => p.id == selected)
          ? selected
          : providers.firstOrNull?.id;
    }

    emit(
      state.copyWith(
        providersByCli: byCli,
        selectedProviderIdByCli: selectedByCli,
        isLoading: false,
        statusMessage: _importStatusMessage(result),
      ),
    );
    return result;
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

  static String _importStatusMessage(ProviderImportResult result) {
    final changed = result.added + result.updated;
    if (changed == 0 && result.mirroredToFlashskyai == 0) {
      return 'No providers imported.';
    }
    return 'Imported $changed providers'
        '${result.mirroredToFlashskyai > 0 ? ', mirrored ${result.mirroredToFlashskyai} to FlashskyAI' : ''}.';
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
