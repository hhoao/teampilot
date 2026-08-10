import 'package:flutter/foundation.dart';

import '../../../../models/app_provider_config.dart';
import '../../registry/capabilities/provider_model_capability.dart';
import 'opencode_model_catalog.dart';
import 'opencode_models_service.dart';

/// OpenCode model catalog from the live models.dev fetch, falling back to the
/// built-in static [OpencodeModelCatalog] (offline / first run before fetch).
final class OpencodeCatalogSource implements ModelCatalogSource {
  const OpencodeCatalogSource(this._modelsService);

  final OpencodeModelsService? _modelsService;

  @override
  List<String> modelsFor({
    required AppProviderConfig? provider,
    required String providerId,
  }) {
    final id = provider?.id ?? providerId;
    final live = _modelsService?.modelIdsFor(providerId: id) ?? const [];
    if (live.isNotEmpty) return live;
    return OpencodeModelCatalog.knownModelsForProvider(id);
  }
}

/// OpenCode's model picker capability with a live models.dev catalog.
final class OpencodeProviderModelCapability extends CatalogModelCapability
    implements RefreshableProviderModelCapability {
  OpencodeProviderModelCapability({OpencodeModelsService? modelsService})
    : _modelsService = modelsService;

  final OpencodeModelsService? _modelsService;

  @override
  bool get supportsModelTiers => false;

  @override
  List<ModelCatalogSource> get catalogSources => [
    OpencodeCatalogSource(_modelsService),
  ];

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
    return service.ensureLoaded(forceRefresh: forceRefresh);
  }

  @override
  ProviderModelPickerMode pickerMode(AppProviderConfig provider) =>
      ProviderModelPickerMode.catalogWithCustomEntry;
}

final _emptyCatalogUpdates = _EmptyListenable();

final class _EmptyListenable implements Listenable {
  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}
