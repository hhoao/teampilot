import '../../registry/capabilities/provider_display_capability.dart';

final class FlashskyaiProviderDisplay implements ProviderDisplayCapability {
  const FlashskyaiProviderDisplay();

  @override bool get hasModelPanel => true;
  @override bool get showModelCount => true;
  @override bool get supportsDelegate => true;
  @override bool get supportsOAuthCredentials => false;
  @override bool get usesLlmConfigJsonPreview => true;
}
