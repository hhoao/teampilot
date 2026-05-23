import '../models/app_provider_config.dart';

/// Collects selectable Claude model ids for a provider (team + onboarding UI).
List<String> collectClaudeModelCandidates(
  AppProviderConfig provider, {
  String currentModel = '',
}) {
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
  final trimmed = currentModel.trim();
  if (trimmed.isNotEmpty) {
    names.add(trimmed);
  }
  return names.toList()..sort();
}