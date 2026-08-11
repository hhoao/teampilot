import '../../../../models/app_provider_config.dart';
import '../../../provider/credential_binding.dart';
import '../cli_capability.dart';

/// How a CLI's official-account providers resolve credentials: follow the
/// global CLI home credential (linked) or use an isolated copy per provider.
///
/// Only CLIs that support the concept register an implementation; the shared
/// resolver in `services/provider/credential_binding.dart` consults this
/// capability instead of hardcoding `if (cli == CliTool.claude)`.
abstract interface class CredentialBindingCapability implements CliCapability {
  /// Whether [provider] can use credential binding (link vs isolated copy).
  bool appliesTo(AppProviderConfig provider);

  /// Binding kind used when the provider's config carries no explicit key.
  CredentialBindingKind defaultBinding(AppProviderConfig provider);

  /// Bakes [binding] into [config] (idempotent).
  Map<String, Object?> withBinding(
    Map<String, Object?> config,
    CredentialBindingKind binding,
  );
}
