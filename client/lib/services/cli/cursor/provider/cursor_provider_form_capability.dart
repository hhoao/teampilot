import '../../../../models/app_provider_config.dart';
import '../provider_presets.dart';
import '../../../provider/passthrough_provider_form_capability.dart';

final class CursorProviderFormCapability
    extends PassthroughProviderFormCapability {
  const CursorProviderFormCapability();

  @override
  List<AppProviderPreset> get presets => CursorProviderPresets.all;

  @override
  Map<String, Object?> defaultConfig() => const {};

  @override
  String defaultApiKeyField() => 'api_key';
}
