import '../../../../models/app_provider_config.dart';
import '../../../../repositories/app_provider_repository.dart';
import '../../../../models/team_config.dart';

class FlashskyaiProviderMirrorResult {
  const FlashskyaiProviderMirrorResult({
    this.added = 0,
    this.skipped = 0,
  });

  final int added;
  final int skipped;
}

/// Mirrors imported provider rows into the flashskyai catalog.
///
/// Lives in the flashskyai CLI directory: the mirror schema (`config['type']`,
/// `provider_type`, `models` nesting) and the "skip flashskyai-origin rows"
/// rule are flashskyai knowledge, not import-service knowledge.
class FlashskyaiProviderMirror {
  FlashskyaiProviderMirror({AppProviderRepository? repository})
    : _repository = repository ?? AppProviderRepository();

  final AppProviderRepository _repository;

  Future<FlashskyaiProviderMirrorResult> mirror(
    List<AppProviderConfig> providers,
  ) async {
    final existing = await _repository.loadProviders(CliTool.flashskyai);
    final byId = {for (final provider in existing) provider.id: provider};
    final existingModelIds = <String>{
      for (final provider in existing) ..._modelIds(provider),
    };
    var added = 0;
    var skipped = 0;
    for (final provider in providers) {
      final mirrored = _toFlashskyaiProvider(
        provider,
        reservedModelIds: existingModelIds,
      );
      if (mirrored == null) continue;
      if (byId.containsKey(mirrored.id)) {
        skipped++;
        continue;
      }
      existingModelIds.addAll(_modelIds(mirrored));
      byId[mirrored.id] = mirrored;
      added++;
    }
    if (added > 0) {
      await _repository.saveProviders(CliTool.flashskyai, byId.values.toList());
    }
    return FlashskyaiProviderMirrorResult(added: added, skipped: skipped);
  }

  AppProviderConfig? _toFlashskyaiProvider(
    AppProviderConfig provider, {
    Set<String> reservedModelIds = const {},
  }) {
    if (provider.cli == CliTool.flashskyai) return null;
    if (provider.id == 'default' &&
        provider.apiKey.trim().isEmpty &&
        provider.baseUrl.trim().isEmpty) {
      return null;
    }
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final model = provider.defaultModel.trim();
    final shouldMirrorModel =
        model.isNotEmpty && !reservedModelIds.contains(model);
    final mirroredDefaultModel = shouldMirrorModel ? model : '';
    final providerType = _providerTypeFor(provider);
    return AppProviderConfig(
      id: provider.id,
      cli: CliTool.flashskyai,
      name: provider.name,
      notes: provider.notes,
      websiteUrl: provider.websiteUrl,
      apiKeyUrl: provider.apiKeyUrl,
      category: provider.category,
      apiKey: provider.apiKey,
      apiKeyField: 'api_key',
      baseUrl: provider.baseUrl,
      defaultModel: mirroredDefaultModel,
      icon: provider.icon,
      iconColor: provider.iconColor,
      isOfficial: provider.isOfficial,
      isPartner: provider.isPartner,
      partnerPromotionKey: provider.partnerPromotionKey,
      endpointCandidates: provider.endpointCandidates,
      config: {
        'type': 'api',
        'provider_type': providerType,
        if (shouldMirrorModel)
          'models': {
            model: {
              'name': model,
              'provider': provider.id,
              'model': model,
              'enabled': true,
            },
          },
      },
      createdAt: now,
      updatedAt: now,
    );
  }

  Set<String> _modelIds(AppProviderConfig provider) {
    final rawModels = provider.config['models'];
    if (rawModels is Map) {
      return rawModels.keys.map((key) => key.toString()).toSet();
    }
    final model = provider.defaultModel.trim();
    if (model.isEmpty) return const {};
    return {model};
  }

  String _providerTypeFor(AppProviderConfig provider) {
    if (provider.cli == CliTool.codex) return 'openai';
    final url = provider.baseUrl.toLowerCase();
    if (url.contains('anthropic') || url.contains('claude')) {
      return 'anthropic';
    }
    return 'openai';
  }
}
