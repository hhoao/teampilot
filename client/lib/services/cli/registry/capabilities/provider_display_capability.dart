import '../cli_capability.dart';

/// Display metadata for a CLI's provider UI — labels, icons, and feature flags.
///
/// Replaces scattered `if (provider.cli == CliTool.X)` checks in the UI layer.
/// Each CLI provides one const instance in its directory.
abstract interface class ProviderDisplayCapability implements CliCapability {
  /// Whether this CLI has a dedicated model-list editor panel (flashskyai).
  bool get hasModelPanel;

  /// Whether the provider list shows a model count badge (flashskyai).
  bool get showModelCount;

  /// Whether credential-status fields are serialized in [AppProviderConfig.toJson].
  bool get serializesCredentialStatus;

  /// Whether this CLI supports credential binding UI (Claude symlink binding).
  bool get hasCredentialBinding;

  /// Whether this CLI appears in the delegate-row team settings UI.
  bool get supportsDelegate;
}
