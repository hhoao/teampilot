import '../../registry/capabilities/provider_display_capability.dart';

final class ClaudeProviderDisplay implements ProviderDisplayCapability {
  const ClaudeProviderDisplay();

  @override bool get hasModelPanel => false;
  @override bool get showModelCount => false;
  @override bool get serializesCredentialStatus => true;
  @override bool get hasCredentialBinding => true;
  @override bool get supportsDelegate => true;
  @override bool get supportsOAuthCredentials => true;
  @override bool get usesLlmConfigJsonPreview => false;
}
