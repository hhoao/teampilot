import 'package:flutter/foundation.dart';

import '../../../models/app_provider_config.dart';
import '../../cli/registry/capabilities/provider_model_capability.dart';
import 'cursor_agent_models_service.dart';

/// Cursor models from `cursor-agent models` (cached per provider account).
final class CursorProviderModelCapability
    implements RefreshableProviderModelCapability {
  CursorProviderModelCapability({CursorAgentModelsService? modelsService})
    : _modelsService = modelsService;

  final CursorAgentModelsService? _modelsService;

  @override
  Listenable get catalogUpdates =>
      _modelsService?.catalogUpdates ?? _emptyCatalogUpdates;

  @override
  Future<void> refreshModelCatalog({
    required String providerId,
    String? executable,
    bool forceRefresh = false,
  }) {
    final service = _modelsService;
    if (service == null) return Future.value();
    return service.ensureLoaded(
      providerId: providerId,
      executable: executable,
      forceRefresh: forceRefresh,
    );
  }

  @override
  ProviderModelPickerMode pickerMode(AppProviderConfig provider) =>
      ProviderModelPickerMode.catalogWithCustomEntry;

  @override
  List<String> modelCandidates({
    required AppProviderConfig? provider,
    required String providerId,
    required String currentModel,
  }) {
    final catalog = _modelsService?.modelIdsFor(providerId: providerId) ?? const [];
    return mergeProviderModelCandidates(
      builtInCatalog: catalog,
      provider: provider,
      currentModel: currentModel,
    );
  }

  @override
  String defaultModel({
    required AppProviderConfig? provider,
    required String providerId,
  }) {
    final fromAgent =
        _modelsService?.defaultModelIdFor(providerId: providerId).trim() ?? '';
    if (fromAgent.isNotEmpty) return fromAgent;
    return resolveDefaultProviderModel(
      this,
      provider: provider,
      providerId: providerId,
    );
  }
}

final _emptyCatalogUpdates = _EmptyListenable();

final class _EmptyListenable implements Listenable {
  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}
