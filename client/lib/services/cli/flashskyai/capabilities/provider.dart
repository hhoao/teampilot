import 'package:flutter/foundation.dart';
import '../../../../models/app_provider_config.dart';
import '../../../../services/provider/credential_binding.dart';
import '../../../../models/credential_probe.dart';
import '../../../../models/credential_action_result.dart';
import '../../../provider/passthrough_provider_form_capability.dart';
import '../../../io/filesystem.dart';
import '../../../remote/remote_credential_materializer.dart';
import '../../registry/capabilities/provider_capability.dart';
import '../../claude/provider/claude_effort_catalog.dart';
import '../provider/flashskyai_live_import.dart';
import '../provider_presets.dart';

/// Flashskyai provider 全栈:目录/表单/模型/effort(无凭证概念)。
final class FlashskyaiProviderCapability extends CatalogModelCapability
    with PassthroughProviderFormDefaults
    implements ProviderCapability {
  const FlashskyaiProviderCapability();

  // ---- ProviderCatalogCapability ----
  @override
  CliTool get catalogCli => CliTool.flashskyai;

  @override
  String? get defaultOfficialProviderId => null;

  @override
  Future<ProviderCatalogSnapshot> loadFromLiveSources(
    ProviderCatalogLoadContext context,
  ) => FlashskyaiLiveImport.loadSnapshot(context);

  // ---- ProviderDisplayCapability ----
  @override
  bool get hasModelPanel => true;
  @override
  bool get showModelCount => true;
  @override
  bool get supportsDelegate => true;
  @override
  bool get supportsOAuthCredentials => false;
  @override
  bool get usesLlmConfigJsonPreview => true;

  // ---- ProviderFormCapability ----
  @override
  List<AppProviderPreset> get presets => FlashskyaiProviderPresets.all;

  @override
  Map<String, Object?> defaultConfig() => {'provider_type': 'openai'};

  @override
  String defaultApiKeyField() => 'api_key';

  // ---- ProviderModelCapability (record semantics) ----
  @override
  bool get supportsModelTiers => false;

  @override
  List<ModelCatalogSource> get catalogSources => const [];

  @override
  ProviderModelPickerMode pickerMode(AppProviderConfig provider) {
    if (provider.isOfficial && provider.defaultModel.trim().isEmpty) {
      return ProviderModelPickerMode.hidden;
    }
    return ProviderModelPickerMode.catalogWithCustomEntry;
  }

  // ---- ProviderModelCapability: live-catalog no-op ----
  @override
  Listenable get catalogUpdates => _emptyCatalogUpdates;

  @override
  Future<void> refreshModelCatalog({
    required String providerId,
    String? executable,
    bool forceRefresh = false,
  }) async {}

  // ---- Credential concept (flashskyai has none) ----
  @override
  bool appliesTo(AppProviderConfig provider) => false;

  @override
  List<ProviderCredentialActionSpec> actionsFor(AppProviderConfig provider) =>
      const [];

  @override
  Future<CredentialProbe> probe(AppProviderConfig provider) async =>
      CredentialProbe(
        providerId: provider.id,
        status: CredentialStatus.missing,
        credentialPath: '',
      );

  @override
  Future<CredentialActionResult> execute({
    required String providerId,
    required ProviderCredentialActionKind kind,
    ProviderCredentialActionInput input = const ProviderCredentialActionInput(),
  }) async => CredentialActionResult.serviceUnavailable();

  @override
  bool hidesApiKeyFields(AppProviderConfig provider) => false;

  @override
  @override
  bool get supportsCredentialBinding => false;

  @override
  CredentialBindingKind defaultBinding(AppProviderConfig provider) =>
      CredentialBindingKind.isolated;

  @override
  Map<String, Object?> withBinding(
    Map<String, Object?> config,
    CredentialBindingKind binding,
  ) => withCredentialBinding(config, binding);

  // ---- CredentialExportCapability ----
  @override
  Future<CredentialFile?> exportCredential({
    required Filesystem fs,
    required String basePath,
    required String home,
    required AppProviderConfig provider,
  }) async => null;

  // ---- CliEffortCapability ----
  @override
  EffortPickerPlacement teamPickerPlacement() => EffortPickerPlacement.team;

  @override
  EffortPickerPlacement memberPickerPlacement({AppProviderConfig? provider}) =>
      EffortPickerPlacement.member;

  @override
  EffortPickerPlacement providerPickerPlacement(AppProviderConfig provider) =>
      EffortPickerPlacement.hidden;

  @override
  bool isApplicable({required String model}) =>
      ClaudeEffortCatalog.modelSupportsEffort(model);

  @override
  List<String> effortCandidates({
    required String model,
    AppProviderConfig? provider,
  }) => ClaudeEffortCatalog.levelsForModel(model);

  @override
  String defaultEffort({required String model, AppProviderConfig? provider}) =>
      ClaudeEffortCatalog.defaultLevel;
}


final _emptyCatalogUpdates = _EmptyListenable();

final class _EmptyListenable implements Listenable {
  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}
