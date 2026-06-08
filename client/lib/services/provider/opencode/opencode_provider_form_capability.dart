import '../../../models/app_provider_config.dart';
import '../../../models/provider_presets/opencode_provider_presets.dart';
import '../passthrough_provider_form_capability.dart';

final class OpencodeProviderFormCapability
    extends PassthroughProviderFormCapability {
  const OpencodeProviderFormCapability();

  @override
  List<AppProviderPreset> get presets => OpencodeProviderPresets.all;

  @override
  Map<String, Object?> defaultConfig() => const {};

  @override
  String defaultApiKeyField() => 'api_key';
}
