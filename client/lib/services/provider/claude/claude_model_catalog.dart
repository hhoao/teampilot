import '../../../models/app_provider_config.dart';
import 'claude_official_provider.dart';

/// Built-in Claude Code model ids and CLI aliases for TeamPilot pickers.
///
/// Aliases match Claude Code (`sonnet`, `opus`, `haiku`, …). Full ids follow
/// Anthropic frontier releases; update when Claude Code bumps defaults.
class ClaudeModelCatalog {
  const ClaudeModelCatalog._();

  /// Short names accepted by `claude --model` (see Claude Code `MODEL_ALIASES`).
  static const aliases = <String>[
    'sonnet',
    'opus',
    'haiku',
    'best',
    'sonnet[1m]',
    'opus[1m]',
    'opusplan',
  ];

  /// First-party Anthropic models (newest first within each tier).
  static const officialModelIds = <String>[
    'claude-opus-4-7',
    'claude-opus-4-6',
    'claude-opus-4-5',
    'claude-opus-4-1',
    'claude-opus-4',
    'claude-sonnet-4-6',
    'claude-sonnet-4-5',
    'claude-sonnet-4',
    'claude-sonnet-3-7',
    'claude-haiku-4-5-20251001',
    'claude-haiku-4-5',
    'claude-haiku-3-5',
  ];

  static const defaultOfficialAlias = 'sonnet';

  static List<String> knownModelsForProvider(AppProviderConfig? provider) {
    if (provider != null && isOfficialClaudeProvider(provider)) {
      return officialModels;
    }
    return const [];
  }

  static List<String> knownModelsForProviderId(
    String providerId, {
    AppProviderConfig? provider,
  }) {
    if (provider != null) {
      return knownModelsForProvider(provider);
    }
    if (providerId.trim() == 'claude-official') {
      return officialModels;
    }
    return const [];
  }

  static List<String> get officialModels => [
    ...aliases,
    ...officialModelIds,
  ];
}
