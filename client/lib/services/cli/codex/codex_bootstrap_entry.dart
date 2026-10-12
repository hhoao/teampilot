import '../../../models/app_provider_config.dart';
import '../registry/cli_bootstrap.dart';
import '../../provider/api_model_catalog_service.dart';
import 'capabilities/acp.dart';
import 'provider/codex_official_provider.dart';
import 'provider/codex_provider_credentials_service.dart';
import 'provider/codex_toml_parser.dart';

final class CodexBootstrapEntry implements CliBootstrapEntry {
  const CodexBootstrapEntry({
    required this.credentialsService,
    this.modelsService,
    this.acpAuthSource,
    this.codexPathSource,
  });

  final CodexProviderCredentialsService credentialsService;
  final ApiModelCatalogService? modelsService;

  /// Sync closure invoked from `CodexAcpCapability.buildEnvironment` at spawn
  /// time. Null → the adapter env carries only `CODEX_HOME` / `CODEX_PATH`.
  final CodexAcpAuthSource? acpAuthSource;

  /// Sync closure for the adapter's `CODEX_PATH` (resolved Codex CLI).
  final String Function()? codexPathSource;
}

/// Picks the Codex provider row that matches [selectedId] (trimmed).
///
/// Empty / missing / unmatched ids fall back to the first Official Codex
/// OAuth row so ACP still links Official credentials via contributeLaunch
/// when the settings picker has no selection yet.
AppProviderConfig? pickCodexAcpProvider({
  required List<AppProviderConfig> providers,
  required String? selectedId,
}) {
  final id = selectedId?.trim() ?? '';
  if (id.isNotEmpty) {
    for (final provider in providers) {
      if (provider.id == id) return provider;
    }
  }
  for (final provider in providers) {
    if (isOfficialCodexOAuthProvider(provider)) return provider;
  }
  return null;
}

/// Maps the current Codex provider row to the ACP launch auth.
///
/// - Official (OAuth) → `official: true`; no API key is ever returned.
/// - Key in the provider's settings env (or its `apiKey` field) →
///   [CodexAcpAuth.apiKey]. Empty / `PROXY_MANAGED` → empty [CodexAcpAuth].
/// - Otherwise (or a null / non-Codex provider) → empty [CodexAcpAuth].
CodexAcpAuth codexAcpAuthForProvider(AppProviderConfig? provider) {
  if (provider == null || provider.cli != CliTool.codex) {
    return const CodexAcpAuth();
  }
  if (isOfficialCodexOAuthProvider(provider)) {
    return const CodexAcpAuth(official: true);
  }
  final rawEnv = provider.config['env'];
  String envValue(String key) =>
      rawEnv is Map ? '${rawEnv[key] ?? ''}'.trim() : '';
  String? nonEmpty(String v) => v.isEmpty ? null : v;

  final apiKey =
      nonEmpty(envValue('OPENAI_API_KEY')) ?? nonEmpty(provider.apiKey.trim());
  if (apiKey == null || apiKey == CodexTomlParser.proxyManagedToken) {
    return const CodexAcpAuth();
  }
  return CodexAcpAuth(apiKey: apiKey);
}
