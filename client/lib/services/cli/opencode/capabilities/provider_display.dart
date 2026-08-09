import '../../registry/capabilities/provider_display_capability.dart';

final class OpencodeProviderDisplay implements ProviderDisplayCapability {
  const OpencodeProviderDisplay();

  @override bool get hasModelPanel => false;
  @override bool get showModelCount => false;
  @override bool get serializesCredentialStatus => false;
  @override bool get hasCredentialBinding => false;
  @override bool get supportsDelegate => false;
}
