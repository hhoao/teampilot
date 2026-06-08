import '../../../models/app_provider_config.dart';
import '../../../models/provider_presets/cursor_provider_presets.dart';
import '../passthrough_provider_form_capability.dart';

final class CursorProviderFormCapability extends PassthroughProviderFormCapability {
  const CursorProviderFormCapability();

  @override
  List<AppProviderPreset> get presets => CursorProviderPresets.all;

  @override
  Map<String, Object?> defaultConfig() => const {};

  @override
  String defaultApiKeyField() => 'api_key';
}
