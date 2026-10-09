import '../../../models/app_provider_config.dart';
import '../registry/cli_bootstrap.dart';
import '../../provider/api_model_catalog_service.dart';
import '../../provider/credential_binding.dart';
import 'capabilities/acp.dart';
import 'provider/claude_official_provider.dart';
import 'provider/claude_provider_credentials_service.dart';

final class ClaudeBootstrapEntry implements CliBootstrapEntry {
  const ClaudeBootstrapEntry({
    required this.credentialsService,
    this.modelsService,
    this.acpAuthSource,
  });

  final ClaudeProviderCredentialsService credentialsService;
  final ApiModelCatalogService? modelsService;

  /// Sync closure invoked from `ClaudeAcpCapability.buildEnvironment` at spawn
  /// time. Null → the adapter env carries only `CLAUDE_CONFIG_DIR`.
  final ClaudeAcpAuthSource? acpAuthSource;
}

/// Picks the Claude provider row that matches [selectedId] (trimmed).
///
/// Empty / missing / unmatched ids return null so [claudeAcpAuthForProvider]
/// yields an empty [ClaudeAcpAuth] (CLAUDE_CONFIG_DIR still set, no keys).
AppProviderConfig? pickClaudeAcpProvider({
  required List<AppProviderConfig> providers,
  required String? selectedId,
}) {
  final id = selectedId?.trim() ?? '';
  if (id.isEmpty) return null;
  for (final provider in providers) {
    if (provider.id == id) return provider;
  }
  return null;
}

/// Maps the current Claude provider row to the ACP launch auth.
///
/// - Official (OAuth) → `official: true` + the effective credential path; no
///   API key / auth token is ever returned.
/// - Key / token in the provider's settings env (or its `apiKey` field) →
///   [ClaudeAcpAuth.apiKey] / [ClaudeAcpAuth.authToken]; `ANTHROPIC_BASE_URL`
///   → [ClaudeAcpAuth.baseUrl].
/// - Otherwise (or a null provider) → empty [ClaudeAcpAuth].
ClaudeAcpAuth claudeAcpAuthForProvider(
  AppProviderConfig? provider,
  ClaudeProviderCredentialsService credentials,
) {
  if (provider == null || provider.cli != CliTool.claude) {
    return const ClaudeAcpAuth();
  }
  if (isOfficialClaudeProvider(provider)) {
    return ClaudeAcpAuth(
      official: true,
      officialCredentialsPath: credentials.effectiveCredentialPath(
        provider.id,
        binding: resolveCredentialBinding(provider),
      ),
    );
  }
  final rawEnv = provider.config['env'];
  String envValue(String key) =>
      rawEnv is Map ? '${rawEnv[key] ?? ''}'.trim() : '';
  String? nonEmpty(String v) => v.isEmpty ? null : v;

  var apiKey = nonEmpty(envValue('ANTHROPIC_API_KEY'));
  var authToken = nonEmpty(envValue('ANTHROPIC_AUTH_TOKEN'));
  final rowKey = nonEmpty(provider.apiKey.trim());
  if (apiKey == null && authToken == null && rowKey != null) {
    if (provider.apiKeyField == 'ANTHROPIC_API_KEY') {
      apiKey = rowKey;
    } else {
      authToken = rowKey;
    }
  }
  return ClaudeAcpAuth(
    apiKey: apiKey,
    authToken: authToken,
    baseUrl: nonEmpty(envValue('ANTHROPIC_BASE_URL')),
  );
}
