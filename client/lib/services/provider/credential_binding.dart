import '../../models/app_provider_config.dart';
import '../cli/registry/capabilities/provider_capability.dart';
import '../cli/registry/cli_tool_registry.dart';

/// How an official-account provider resolves OAuth / credential files.
enum CredentialBindingKind {
  /// Symlink TeamPilot provider + session paths to the global CLI home credential.
  linked('linked'),

  /// Copy credentials into `<teampilotRoot>/providers/{cli}/{id}/`.
  isolated('isolated');

  const CredentialBindingKind(this.value);

  final String value;

  static CredentialBindingKind parse(Object? raw) {
    final normalized = raw?.toString().trim().toLowerCase() ?? '';
    for (final kind in CredentialBindingKind.values) {
      if (kind.value == normalized) return kind;
    }
    return CredentialBindingKind.linked;
  }
}

/// Config key under [AppProviderConfig.config] for [CredentialBindingKind].
const credentialBindingConfigKey = 'credentialBinding';

/// Resolves the binding for [provider]: an explicit config key wins; otherwise
/// the provider's CLI capability decides (Claude official → global link).
CredentialBindingKind resolveCredentialBinding(
  AppProviderConfig provider, {
  CliToolRegistry? registry,
}) {
  final raw = provider.config[credentialBindingConfigKey];
  if (raw != null) {
    return CredentialBindingKind.parse(raw);
  }
  final capability = (registry ?? CliToolRegistry.builtIn())
      .capability<ProviderCapability>(provider.cli);
  return capability?.defaultBinding(provider) ?? CredentialBindingKind.isolated;
}

Map<String, Object?> withCredentialBinding(
  Map<String, Object?> config,
  CredentialBindingKind binding,
) {
  return {...config, credentialBindingConfigKey: binding.value};
}

String globalClaudeCredentialPath(String homeDirectory, dynamic pathContext) {
  return pathContext.join(homeDirectory.trim(), '.claude', '.credentials.json');
}
