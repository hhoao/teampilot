import '../../models/app_provider_config.dart';
import 'claude/claude_official_provider.dart';

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

/// Default official Claude providers follow the global `~/.claude` credential.
CredentialBindingKind resolveCredentialBinding(AppProviderConfig provider) {
  final raw = provider.config[credentialBindingConfigKey];
  if (raw != null) {
    return CredentialBindingKind.parse(raw);
  }
  if (provider.cli == CliTool.claude && isOfficialClaudeProvider(provider)) {
    return CredentialBindingKind.linked;
  }
  return CredentialBindingKind.isolated;
}

Map<String, Object?> withCredentialBinding(
  Map<String, Object?> config,
  CredentialBindingKind binding,
) {
  return {...config, credentialBindingConfigKey: binding.value};
}

String globalClaudeCredentialPath(String homeDirectory, dynamic pathContext) {
  return pathContext.join(
    homeDirectory.trim(),
    '.claude',
    '.credentials.json',
  );
}
