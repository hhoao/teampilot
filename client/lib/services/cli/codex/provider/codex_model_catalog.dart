import '../../../../models/app_provider_config.dart';
import 'codex_official_provider.dart';

/// Built-in OpenAI/Codex model ids used when OAuth cannot expose `/models`.
///
/// API-key providers use their live OpenAI-compatible catalog. This list is
/// intentionally limited to the first-party OAuth provider and is updated
/// alongside the official model lineup.
class CodexModelCatalog {
  const CodexModelCatalog._();

  static const officialModelIds = <String>[
    'gpt-5.6-luna',
    'gpt-5.6-sol',
    'gpt-5.6-terra',
    'gpt-5.5',
    'gpt-5.5-pro',
    'gpt-5.4',
    'gpt-5.4-mini',
    'gpt-5.4-nano',
    'gpt-5.4-pro',
    'gpt-5.3-codex',
    'gpt-5.3-codex-spark',
    'gpt-5.2',
    'gpt-5.2-codex',
    'gpt-5.1-codex-max',
    'gpt-5.1-codex',
    'gpt-5.1-codex-mini',
    'gpt-5-codex',
  ];

  static List<String> knownModelsForProvider(AppProviderConfig? provider) {
    if (provider != null && isOfficialCodexOAuthProvider(provider)) {
      return officialModels;
    }
    return const [];
  }

  static List<String> knownModelsForProviderId(
    String providerId, {
    AppProviderConfig? provider,
  }) {
    if (provider != null) return knownModelsForProvider(provider);
    return providerId.trim() == 'openai-official' ? officialModels : const [];
  }

  static List<String> get officialModels => [...officialModelIds];
}
