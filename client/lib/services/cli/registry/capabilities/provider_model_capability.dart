import 'package:flutter/foundation.dart';

import '../../../../models/app_provider_config.dart';
import '../../../provider/opencode/opencode_model_catalog.dart';
import '../cli_capability.dart';

/// Model catalog that can be refreshed asynchronously (e.g. `cursor-agent models`).
abstract interface class RefreshableProviderModelCapability
    implements ProviderModelCapability {
  Listenable get catalogUpdates;

  Future<void> refreshModelCatalog({
    required String providerId,
    String? executable,
    bool forceRefresh = false,
  });
}

/// How member / workspace UI should collect a model id for a provider.
enum ProviderModelPickerMode {
  /// Provider bundles models (e.g. Claude official); no member model field.
  hidden,

  /// Pick from catalog only ([ProviderModelPickerMode.catalogDropdown]).
  catalogDropdown,

  /// Catalog dropdown plus free-form custom model id entry.
  catalogWithCustomEntry,
}

/// Per-CLI model catalog and picker rules for team / workspace configuration UI.
abstract interface class ProviderModelCapability implements CliCapability {
  ProviderModelPickerMode pickerMode(AppProviderConfig provider);

  List<String> modelCandidates({
    required AppProviderConfig? provider,
    required String providerId,
    required String currentModel,
  });

  String defaultModel({
    required AppProviderConfig? provider,
    required String providerId,
  });

  /// Whether this CLI resolves model requests through tiers (e.g. Claude's
  /// haiku/sonnet/opus). When true, a model in the provider's list may be
  /// flagged with [ProviderModelTier.background] to serve the cheap/fast tier
  /// while the selected model drives the main tiers; the launch materializer
  /// reads that role. When false, model selection is flat and tier roles are
  /// hidden in the UI and ignored at launch.
  bool get supportsModelTiers;
}

/// Role a model plays within a tier-aware CLI's launch config.
enum ProviderModelTier {
  /// Serves the main tiers (Claude sonnet/opus + the primary model id).
  standard('standard'),

  /// Serves the cheap/fast background tier (Claude haiku).
  background('background');

  const ProviderModelTier(this.value);

  final String value;

  static ProviderModelTier fromJson(Object? raw) {
    final s = raw?.toString().trim().toLowerCase() ?? '';
    for (final tier in ProviderModelTier.values) {
      if (tier.value == s) return tier;
    }
    return ProviderModelTier.standard;
  }
}

/// The model id flagged as the [ProviderModelTier.background] tier in the
/// provider's `config['models']`, or '' when none is designated.
String backgroundModelFromProvider(AppProviderConfig? provider) {
  if (provider == null) return '';
  final rawModels = provider.config['models'];
  if (rawModels is! Map) return '';
  for (final entry in rawModels.entries) {
    final value = entry.value;
    if (value is! Map) continue;
    final role = ProviderModelTier.fromJson(value['role']);
    if (role != ProviderModelTier.background) continue;
    final model = (value['model'] as String? ?? '').trim();
    return model.isNotEmpty ? model : entry.key.toString().trim();
  }
  return '';
}

/// Merges a CLI built-in catalog with models declared on [AppProviderConfig].
List<String> mergeProviderModelCandidates({
  required Iterable<String> builtInCatalog,
  required AppProviderConfig? provider,
  required String currentModel,
}) {
  final names = <String>{...builtInCatalog};
  if (provider != null) {
    names.addAll(modelsDeclaredOnProvider(provider));
  }
  final trimmed = currentModel.trim();
  if (trimmed.isNotEmpty) {
    names.add(trimmed);
  }
  return names.toList()..sort();
}

/// Reads `defaultModel` and `config.models` from a saved provider row.
List<String> modelsDeclaredOnProvider(AppProviderConfig provider) {
  final names = <String>{};
  final defaultModel = provider.defaultModel.trim();
  if (defaultModel.isNotEmpty) {
    names.add(defaultModel);
  }
  final rawModels = provider.config['models'];
  if (rawModels is Map) {
    for (final entry in rawModels.entries) {
      final id = entry.key.toString().trim();
      if (entry.value is Map) {
        final modelJson = Map<String, Object?>.from(entry.value as Map);
        final name = (modelJson['name'] as String? ?? '').trim();
        final model = (modelJson['model'] as String? ?? '').trim();
        if (name.isNotEmpty) names.add(name);
        if (model.isNotEmpty) names.add(model);
      } else if (id.isNotEmpty) {
        names.add(id);
      }
    }
  }
  return names.toList();
}

String resolveDefaultProviderModel(ProviderModelCapability capability, {
  required AppProviderConfig? provider,
  required String providerId,
}) {
  if (provider != null &&
      capability.pickerMode(provider) == ProviderModelPickerMode.hidden) {
    return '';
  }
  final fromProvider = provider?.defaultModel.trim() ?? '';
  if (fromProvider.isNotEmpty) return fromProvider;
  final candidates = capability.modelCandidates(
    provider: provider,
    providerId: providerId,
    currentModel: '',
  );
  return candidates.isNotEmpty ? candidates.first : '';
}

/// One composable source of built-in candidate model ids for a provider.
///
/// The provider record itself (`defaultModel` + `config['models']`) is always
/// merged on top of these by [CatalogModelCapability], so a source only
/// contributes the CLI's *built-in* knowledge (a fixed catalog, a brand list,
/// or a live `cursor-agent models` fetch). Adding a CLI = declaring its
/// [CatalogModelCapability.catalogSources].
abstract interface class ModelCatalogSource {
  List<String> modelsFor({
    required AppProviderConfig? provider,
    required String providerId,
  });
}

/// [ProviderModelCapability] whose candidates are the union of its
/// [catalogSources] plus the provider record and the current value.
abstract base class CatalogModelCapability implements ProviderModelCapability {
  const CatalogModelCapability();

  /// Built-in catalogs merged before the provider record. Order is irrelevant
  /// (results are deduped and sorted).
  List<ModelCatalogSource> get catalogSources;

  @override
  List<String> modelCandidates({
    required AppProviderConfig? provider,
    required String providerId,
    required String currentModel,
  }) {
    final builtIn = <String>[];
    for (final source in catalogSources) {
      builtIn.addAll(source.modelsFor(provider: provider, providerId: providerId));
    }
    return mergeProviderModelCandidates(
      builtInCatalog: builtIn,
      provider: provider,
      currentModel: currentModel,
    );
  }

  @override
  String defaultModel({
    required AppProviderConfig? provider,
    required String providerId,
  }) => resolveDefaultProviderModel(this, provider: provider, providerId: providerId);
}

/// OpenCode's built-in Zen / direct-API catalog keyed by provider id.
final class OpencodeCatalogSource implements ModelCatalogSource {
  const OpencodeCatalogSource();

  @override
  List<String> modelsFor({
    required AppProviderConfig? provider,
    required String providerId,
  }) =>
      OpencodeModelCatalog.knownModelsForProvider(provider?.id ?? providerId);
}

final class OpencodeProviderModelCapability extends CatalogModelCapability {
  const OpencodeProviderModelCapability();

  @override
  bool get supportsModelTiers => false;

  @override
  List<ModelCatalogSource> get catalogSources =>
      const [OpencodeCatalogSource()];

  @override
  ProviderModelPickerMode pickerMode(AppProviderConfig provider) =>
      ProviderModelPickerMode.catalogWithCustomEntry;
}

/// Catalog from the provider record only; supports custom model ids.
final class ProviderRecordModelCapability extends CatalogModelCapability {
  const ProviderRecordModelCapability();

  @override
  bool get supportsModelTiers => false;

  @override
  List<ModelCatalogSource> get catalogSources => const [];

  @override
  ProviderModelPickerMode pickerMode(AppProviderConfig provider) {
    if (provider.isOfficial && provider.defaultModel.trim().isEmpty) {
      return ProviderModelPickerMode.hidden;
    }
    return ProviderModelPickerMode.catalogWithCustomEntry;
  }
}
