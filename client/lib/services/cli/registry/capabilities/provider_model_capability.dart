import '../../../../models/app_provider_config.dart';
import '../../../provider/claude/claude_official_provider.dart';
import '../../../provider/opencode/opencode_model_catalog.dart';
import '../cli_capability.dart';

/// How member / project UI should collect a model id for a provider.
enum ProviderModelPickerMode {
  /// Provider bundles models (e.g. Claude official); no member model field.
  hidden,

  /// Pick from catalog only ([ProviderModelPickerMode.catalogDropdown]).
  catalogDropdown,

  /// Catalog dropdown plus free-form custom model id entry.
  catalogWithCustomEntry,
}

/// Per-CLI model catalog and picker rules for team / project configuration UI.
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

final class ClaudeProviderModelCapability implements ProviderModelCapability {
  const ClaudeProviderModelCapability();

  @override
  ProviderModelPickerMode pickerMode(AppProviderConfig provider) =>
      isOfficialClaudeProvider(provider)
      ? ProviderModelPickerMode.hidden
      : ProviderModelPickerMode.catalogDropdown;

  @override
  List<String> modelCandidates({
    required AppProviderConfig? provider,
    required String providerId,
    required String currentModel,
  }) =>
      mergeProviderModelCandidates(
        builtInCatalog: const [],
        provider: provider,
        currentModel: currentModel,
      );

  @override
  String defaultModel({
    required AppProviderConfig? provider,
    required String providerId,
  }) => resolveDefaultProviderModel(this, provider: provider, providerId: providerId);
}

final class OpencodeProviderModelCapability implements ProviderModelCapability {
  const OpencodeProviderModelCapability();

  @override
  ProviderModelPickerMode pickerMode(AppProviderConfig provider) =>
      ProviderModelPickerMode.catalogWithCustomEntry;

  @override
  List<String> modelCandidates({
    required AppProviderConfig? provider,
    required String providerId,
    required String currentModel,
  }) {
    final catalog = provider != null
        ? OpencodeModelCatalog.knownModelsForProvider(provider.id)
        : OpencodeModelCatalog.knownModelsForProvider(providerId);
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
  }) => resolveDefaultProviderModel(this, provider: provider, providerId: providerId);
}

/// Catalog from the provider record only; supports custom model ids.
final class ProviderRecordModelCapability implements ProviderModelCapability {
  const ProviderRecordModelCapability();

  @override
  ProviderModelPickerMode pickerMode(AppProviderConfig provider) {
    if (provider.isOfficial && provider.defaultModel.trim().isEmpty) {
      return ProviderModelPickerMode.hidden;
    }
    return ProviderModelPickerMode.catalogWithCustomEntry;
  }

  @override
  List<String> modelCandidates({
    required AppProviderConfig? provider,
    required String providerId,
    required String currentModel,
  }) =>
      mergeProviderModelCandidates(
        builtInCatalog: const [],
        provider: provider,
        currentModel: currentModel,
      );

  @override
  String defaultModel({
    required AppProviderConfig? provider,
    required String providerId,
  }) => resolveDefaultProviderModel(this, provider: provider, providerId: providerId);
}
