import '../../../../models/app_provider_config.dart';
import '../../../../models/team_config.dart';
import '../provider_presets.dart';

/// How an OpenCode provider acquires and stores credentials in TeamPilot.
///
/// OpenCode CLIs read `auth.json` and/or `opencode.json` `options.apiKey` at
/// runtime. TeamPilot keeps a single catalog source of truth (`AppProviderConfig`)
/// and materializes CLI artifacts at launch — no separate OAuth login flow.
enum OpencodeCredentialKind {
  /// Provider does not require credentials (local / hypothetical).
  none,

  /// API key entered in the provider form (`AppProviderConfig.apiKey`).
  apiKey,

  /// Full `auth.json` provider entry (e.g. OAuth tokens from live import).
  /// Stored in `config['authEntry']` until a dedicated vault exists.
  authEntry,
}

/// Config key for [OpencodeCredentialKind] on provider presets / rows.
abstract final class OpencodeCredentialConfigKeys {
  OpencodeCredentialConfigKeys._();

  static const kind = 'credentialKind';
  static const authEntry = 'authEntry';
}

abstract final class OpencodeCredentialKindResolver {
  OpencodeCredentialKindResolver._();

  static OpencodeCredentialKind forProvider(AppProviderConfig provider) {
    if (provider.cli != CliTool.opencode) return OpencodeCredentialKind.none;

    final fromConfig = _parse(provider.config[OpencodeCredentialConfigKeys.kind]);
    if (fromConfig != null) return fromConfig;

    final preset = OpencodeProviderPresets.byId(provider.id);
    if (preset != null) {
      final fromPreset = _parse(
        preset.template.config[OpencodeCredentialConfigKeys.kind],
      );
      if (fromPreset != null) return fromPreset;
    }

    return OpencodeCredentialKind.apiKey;
  }

  static bool needsCredential(AppProviderConfig provider) =>
      forProvider(provider) != OpencodeCredentialKind.none;

  static OpencodeCredentialKind? _parse(Object? raw) {
    final value = raw?.toString().trim() ?? '';
    if (value.isEmpty) return null;
    return switch (value) {
      'none' => OpencodeCredentialKind.none,
      'apiKey' => OpencodeCredentialKind.apiKey,
      'authEntry' => OpencodeCredentialKind.authEntry,
      _ => null,
    };
  }
}
