import '../../../../models/app_provider_config.dart';
import '../provider_presets.dart';
import '../../../provider/passthrough_provider_form_capability.dart';

final class FlashskyaiProviderFormCapability
    extends PassthroughProviderFormCapability {
  const FlashskyaiProviderFormCapability();

  @override
  List<AppProviderPreset> get presets => FlashskyaiProviderPresets.all;

  @override
  Map<String, Object?> defaultConfig() => {'provider_type': 'openai'};

  @override
  String defaultApiKeyField() => 'api_key';
}
