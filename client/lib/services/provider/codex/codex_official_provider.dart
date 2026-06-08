import '../../../models/app_provider_config.dart';

/// OpenAI ChatGPT OAuth via `codex login` (not API-key proxy presets).
bool isOfficialCodexOAuthProvider(AppProviderConfig provider) {
  if (provider.cli != CliTool.codex || !provider.isOfficial) return false;
  return provider.id == 'openai-official';
}
