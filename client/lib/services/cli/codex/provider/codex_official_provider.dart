import '../../../../models/app_provider_config.dart';

/// OpenAI ChatGPT OAuth via `codex login` (not API-key proxy presets).
///
/// Matched by category instead of a hard-coded id so duplicate rows created
/// from the official preset (e.g. `openai-official-2`) keep their login /
/// import / probe / launch-credential capabilities.
bool isOfficialCodexOAuthProvider(AppProviderConfig provider) {
  if (provider.cli != CliTool.codex || !provider.isOfficial) return false;
  return provider.category == AppProviderCategory.official;
}
