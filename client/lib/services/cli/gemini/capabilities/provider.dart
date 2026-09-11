import 'package:flutter/foundation.dart';

import '../../../../models/app_provider_config.dart';
import '../../../../models/credential_action_result.dart';
import '../../../../models/credential_probe.dart';
import '../../../io/filesystem.dart';
import '../../../provider/credential_binding.dart';
import '../../../provider/passthrough_provider_form_capability.dart';
import '../../../remote/remote_credential_materializer.dart';
import '../../registry/capabilities/provider_capability.dart';

/// Static built-in Gemini model catalog for this phase (consulted the google
/// entry of opencode_model_catalog.dart for current naming). Task 8+ (ACP)
/// revisits whether a live catalog is needed.
abstract final class GeminiModelCatalog {
  const GeminiModelCatalog._();

  static const googleModels = <String>[
    'gemini-2.5-pro',
    'gemini-2.5-flash',
    'gemini-3-flash',
  ];

  static List<String> modelsFor({
    required AppProviderConfig? provider,
    required String providerId,
  }) => googleModels;
}

final class _GeminiCatalogSource implements ModelCatalogSource {
  const _GeminiCatalogSource();

  @override
  List<String> modelsFor({
    required AppProviderConfig? provider,
    required String providerId,
  }) =>
      GeminiModelCatalog.modelsFor(provider: provider, providerId: providerId);
}

/// Gemini provider minimal stack: static model catalog, passthrough form, no
/// credential concepts (no CLI login flow in this phase). [materializeSessionHome]
/// only writes the isolated GEMINI_CONFIG_DIR; the API key reaches the CLI
/// process through the ACP environment (GeminiAcpCapability).
final class GeminiProviderCapability extends CatalogModelCapability
    with PassthroughProviderFormDefaults
    implements ProviderCapability {
  const GeminiProviderCapability();

  // ---- ProviderCatalogCapability ----
  @override
  CliTool get catalogCli => CliTool.gemini;

  @override
  String? get defaultOfficialProviderId => 'google';

  @override
  Future<ProviderCatalogSnapshot> loadFromLiveSources(
    ProviderCatalogLoadContext context,
  ) async => const ProviderCatalogSnapshot();

  // ---- ProviderDisplayCapability ----
  @override
  bool get hasModelPanel => false;
  @override
  bool get showModelCount => false;
  @override
  bool get supportsDelegate => false;
  @override
  bool get supportsOAuthCredentials => false;
  @override
  bool get usesLlmConfigJsonPreview => false;

  // ---- ProviderFormCapability ----
  @override
  List<AppProviderPreset> get presets => const [
    AppProviderPreset(
      id: 'google',
      label: 'Google AI Studio',
      template: AppProviderConfig(
        id: 'google',
        cli: CliTool.gemini,
        name: 'Google AI Studio',
        websiteUrl: 'https://ai.google.dev',
        apiKeyUrl: 'https://aistudio.google.com/apikey',
        category: AppProviderCategory.official,
        defaultModel: 'gemini-2.5-pro',
        icon: 'gemini',
      ),
    ),
  ];

  @override
  Map<String, Object?> defaultConfig() => const {};

  @override
  String defaultApiKeyField() => 'api_key';

  // ---- ProviderModelCapability (static catalog) ----
  @override
  bool get supportsModelTiers => false;

  @override
  List<ModelCatalogSource> get catalogSources => const [_GeminiCatalogSource()];

  @override
  ProviderModelPickerMode pickerMode(AppProviderConfig provider) =>
      ProviderModelPickerMode.catalogWithCustomEntry;

  // ---- ProviderModelCapability: live-catalog no-op (static catalog) ----
  @override
  Listenable get catalogUpdates => _emptyCatalogUpdates;

  @override
  Future<void> refreshModelCatalog({
    required String providerId,
    AppProviderConfig? provider,
    String? executable,
    bool forceRefresh = false,
  }) async {}

  // ---- ProviderCredentialCapability (no CLI login flow this phase) ----
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
  }) async => CredentialActionResult.unsupported();

  @override
  bool hidesApiKeyFields(AppProviderConfig provider) => false;

  // ---- CredentialBindingCapability (no concept: isolated) ----
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
  EffortPickerPlacement teamPickerPlacement() => EffortPickerPlacement.hidden;

  @override
  EffortPickerPlacement memberPickerPlacement({AppProviderConfig? provider}) =>
      EffortPickerPlacement.hidden;

  @override
  EffortPickerPlacement providerPickerPlacement(AppProviderConfig provider) =>
      EffortPickerPlacement.hidden;

  @override
  bool isApplicable({required String model}) => false;

  @override
  List<String> effortCandidates({
    required String model,
    AppProviderConfig? provider,
  }) => const [];

  @override
  String defaultEffort({required String model, AppProviderConfig? provider}) =>
      '';

  // ---- Session-home materialization ----
  static const configDirEnvKey = 'GEMINI_CONFIG_DIR';

  @override
  Future<SessionHomeContribution> materializeSessionHome(
    SessionHomeContext ctx,
  ) async {
    final delegate = ctx.paths;
    final configDir = delegate.sessionToolDir(
      ctx.scope.workspaceId,
      ctx.scope.sessionId,
      CliTool.gemini.value,
      memberId: ctx.scope.memberId,
    );
    await delegate.fs.ensureDir(configDir);
    // Minimal home: point Gemini at the session CONFIG_DIR. Credential
    // materialization (API key / OAuth) is deferred to the ACP session
    // runtime (tasks 8-9); nothing is written here yet.
    return SessionHomeContribution(environment: {configDirEnvKey: configDir});
  }
}

final _emptyCatalogUpdates = _EmptyListenable();

final class _EmptyListenable implements Listenable {
  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}
