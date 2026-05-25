import '../../models/app_provider_config.dart';

bool isOfficialClaudeProvider(AppProviderConfig provider) {
  if (provider.cli != AppProviderCli.claude) return false;
  if (provider.category != AppProviderCategory.official) return false;
  return isOfficialClaudeSettings(provider.config);
}

bool isOfficialClaudeSettings(Map<String, Object?> settings) {
  final rawEnv = settings['env'];
  if (rawEnv is! Map) return true;
  final env = rawEnv.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''));
  bool has(String key) => (env[key] ?? '').trim().isNotEmpty;
  if (has('ANTHROPIC_BASE_URL')) return false;
  if (has('ANTHROPIC_AUTH_TOKEN')) return false;
  if (has('ANTHROPIC_API_KEY')) return false;
  return true;
}
