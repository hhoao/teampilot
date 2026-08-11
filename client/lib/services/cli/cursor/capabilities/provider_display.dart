import '../../registry/capabilities/provider_display_capability.dart';

final class CursorProviderDisplay implements ProviderDisplayCapability {
  const CursorProviderDisplay();

  @override bool get hasModelPanel => false;
  @override bool get showModelCount => false;
  @override bool get supportsDelegate => false;
  @override bool get supportsOAuthCredentials => true;
  @override bool get usesLlmConfigJsonPreview => false;
}
