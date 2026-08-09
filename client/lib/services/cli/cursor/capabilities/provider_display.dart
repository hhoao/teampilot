import '../../registry/capabilities/provider_display_capability.dart';

final class CursorProviderDisplay implements ProviderDisplayCapability {
  const CursorProviderDisplay();

  @override bool get hasModelPanel => false;
  @override bool get showModelCount => false;
  @override bool get serializesCredentialStatus => true;
  @override bool get hasCredentialBinding => false;
  @override bool get supportsDelegate => false;
}
