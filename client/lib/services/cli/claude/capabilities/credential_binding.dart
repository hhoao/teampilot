import '../../../../models/app_provider_config.dart';
import '../../../provider/credential_binding.dart';
import '../../registry/capabilities/credential_binding_capability.dart';
import '../provider/claude_official_provider.dart';

/// Official Claude providers follow the global `~/.claude` credential unless
/// the provider row opts into an isolated copy.
final class ClaudeCredentialBindingCapability
    implements CredentialBindingCapability {
  const ClaudeCredentialBindingCapability();

  @override
  bool appliesTo(AppProviderConfig provider) =>
      isOfficialClaudeProvider(provider);

  @override
  CredentialBindingKind defaultBinding(AppProviderConfig provider) =>
      isOfficialClaudeProvider(provider)
          ? CredentialBindingKind.linked
          : CredentialBindingKind.isolated;

  @override
  Map<String, Object?> withBinding(
    Map<String, Object?> config,
    CredentialBindingKind binding,
  ) => withCredentialBinding(config, binding);
}
