import 'package:flutter/foundation.dart';

import '../../../../models/app_provider_config.dart';
import '../../../../models/credential_action_result.dart';
import '../../../../models/credential_probe.dart';
import '../../../provider/credential_binding.dart';
import '../../../provider/passthrough_provider_form_capability.dart';
import '../../../io/filesystem.dart';
import '../../../remote/remote_credential_materializer.dart';
import '../../registry/capabilities/credential_export_capability.dart' show CredentialExportCapability;
import '../../registry/capabilities/provider_capability.dart';
import '../../registry/capabilities/provider_catalog_capability.dart' show ProviderCatalogCapability;
import '../../registry/capabilities/provider_credential_capability.dart' show ProviderCredentialCapability;
import '../../registry/capabilities/provider_display_capability.dart' show ProviderDisplayCapability;
import '../../registry/capabilities/provider_form_capability.dart' show ProviderFormCapability;
import '../../registry/capabilities/provider_model_capability.dart' show ProviderModelCapability, RefreshableProviderModelCapability;
import '../provider/cursor_agent_models_service.dart';
import '../provider/cursor_live_import.dart';
import '../provider/cursor_provider_credentials_service.dart';
import '../provider_presets.dart';

/// Live `cursor-agent models` catalog (cached per provider account).
final class CursorAgentCatalogSource implements ModelCatalogSource {
  const CursorAgentCatalogSource(this._modelsService);

  final CursorAgentModelsService? _modelsService;

  @override
  List<String> modelsFor({
    required AppProviderConfig? provider,
    required String providerId,
  }) => _modelsService?.modelIdsFor(providerId: providerId) ?? const [];
}

/// Cursor provider 全栈:目录/表单/模型(实时目录)/凭证/导出。
final class CursorProviderCapability extends CatalogModelCapability
    with PassthroughProviderFormDefaults
    implements
        ProviderCapability,
        ProviderCatalogCapability,
        ProviderDisplayCapability,
        ProviderFormCapability,
        ProviderModelCapability,
        RefreshableProviderModelCapability,
        ProviderCredentialCapability,
        CredentialExportCapability {
  const CursorProviderCapability({
    CursorAgentModelsService? modelsService,
    CursorProviderCredentialsService? credentials,
  }) : _modelsService = modelsService,
       _credentials = credentials;

  final CursorAgentModelsService? _modelsService;
  final CursorProviderCredentialsService? _credentials;

  CursorProviderCredentialsService? get _service => _credentials;

  // ---- ProviderCatalogCapability ----
  @override
  CliTool get catalogCli => CliTool.cursor;

  @override
  String? get defaultOfficialProviderId => 'cursor-account';

  @override
  Future<ProviderCatalogSnapshot> loadFromLiveSources(
    ProviderCatalogLoadContext context,
  ) => CursorLiveImport.loadSnapshot(context);

  // ---- ProviderDisplayCapability ----
  @override
  bool get hasModelPanel => false;
  @override
  bool get showModelCount => false;
  @override
  bool get supportsDelegate => false;
  @override
  bool get supportsOAuthCredentials => true;
  @override
  bool get usesLlmConfigJsonPreview => false;

  // ---- ProviderFormCapability ----
  @override
  List<AppProviderPreset> get presets => CursorProviderPresets.all;

  @override
  Map<String, Object?> defaultConfig() => const {};

  @override
  String defaultApiKeyField() => 'api_key';

  // ---- ProviderModelCapability (live `cursor-agent models`) ----
  @override
  bool get supportsModelTiers => false;

  @override
  List<ModelCatalogSource> get catalogSources => [
    CursorAgentCatalogSource(_modelsService),
  ];

  @override
  Listenable get catalogUpdates =>
      _modelsService?.catalogUpdates ?? _emptyCatalogUpdates;

  @override
  Future<void> refreshModelCatalog({
    required String providerId,
    String? executable,
    bool forceRefresh = false,
  }) {
    final service = _modelsService;
    if (service == null) return Future.value();
    return service.ensureLoaded(
      providerId: providerId,
      executable: executable,
      forceRefresh: forceRefresh,
    );
  }

  @override
  ProviderModelPickerMode pickerMode(AppProviderConfig provider) =>
      ProviderModelPickerMode.catalogWithCustomEntry;

  @override
  String defaultModel({
    required AppProviderConfig? provider,
    required String providerId,
  }) {
    final fromAgent =
        _modelsService?.defaultModelIdFor(providerId: providerId).trim() ?? '';
    if (fromAgent.isNotEmpty) return fromAgent;
    return resolveDefaultProviderModel(
      this,
      provider: provider,
      providerId: providerId,
    );
  }

  // ---- ProviderCredentialCapability ----
  @override
  bool appliesTo(AppProviderConfig provider) =>
      provider.cli == CliTool.cursor && provider.isOfficial;

  @override
  bool hidesApiKeyFields(AppProviderConfig provider) => appliesTo(provider);

  @override
  List<ProviderCredentialActionSpec> actionsFor(AppProviderConfig provider) {
    if (!appliesTo(provider)) return const [];
    return const [
      ProviderCredentialActionSpec(
        kind: ProviderCredentialActionKind.login,
        primary: true,
        showWhenReady: false,
      ),
      ProviderCredentialActionSpec(
        kind: ProviderCredentialActionKind.importGlobal,
      ),
      ProviderCredentialActionSpec(
        kind: ProviderCredentialActionKind.importDirectory,
      ),
      ProviderCredentialActionSpec(
        kind: ProviderCredentialActionKind.revoke,
        showWhenReady: true,
      ),
    ];
  }

  @override
  Future<CredentialProbe> probe(AppProviderConfig provider) async {
    final service = _service;
    if (service == null) {
      return CredentialProbe(
        providerId: provider.id,
        status: CredentialStatus.missing,
        credentialPath: '',
      );
    }
    return service.probe(provider.id);
  }

  @override
  Future<CredentialActionResult> execute({
    required String providerId,
    required ProviderCredentialActionKind kind,
    ProviderCredentialActionInput input = const ProviderCredentialActionInput(),
  }) async {
    final service = _service;
    if (service == null) return CredentialActionResult.serviceUnavailable();
    final path = input.pickedPath?.trim() ?? '';
    return switch (kind) {
      ProviderCredentialActionKind.login => service.runAuthLogin(providerId),
      ProviderCredentialActionKind.importGlobal => service.importFromGlobal(
        providerId,
        homeDirectory: input.homeDirectory?.trim() ?? '',
        replace: input.replace,
      ),
      ProviderCredentialActionKind.importDirectory =>
        path.isEmpty
            ? CredentialActionResult.failure(
                const CredentialActionFailure(
                  code: CredentialActionFailureCode.pathRequired,
                ),
              )
            : _importCursorPath(
                service,
                providerId: providerId,
                path: path,
                replace: input.replace,
              ),
      ProviderCredentialActionKind.importFile =>
        path.isEmpty
            ? CredentialActionResult.failure(
                const CredentialActionFailure(
                  code: CredentialActionFailureCode.pathRequired,
                ),
              )
            : service.importAuthJsonFile(
                providerId,
                path,
                replace: input.replace,
              ),
      ProviderCredentialActionKind.revoke => service.revokeCredentials(
        providerId,
      ),
    };
  }

  // ---- CredentialBindingCapability (no concept: fall back to isolated) ----
  @override
  CredentialBindingKind defaultBinding(AppProviderConfig provider) =>
      CredentialBindingKind.isolated;

  @override
  Map<String, Object?> withBinding(
    Map<String, Object?> config,
    CredentialBindingKind binding,
  ) => withCredentialBinding(config, binding);

  // ---- CliEffortCapability (not supported) ----
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

  // ---- CredentialExportCapability ----
  @override
  Future<CredentialFile?> exportCredential({
    required Filesystem fs,
    required String basePath,
    required String home,
    required AppProviderConfig provider,
  }) async {
    final toolRoot = fs.pathContext.join(
      basePath,
      'providers',
      provider.cli.value,
    );
    final probe = await CursorProviderCredentialsService(
      fs: fs,
      basePath: basePath,
    ).probe(provider.id);
    if (!probe.isReady) return null;
    final content = await fs.readString(probe.credentialPath);
    if (content == null || content.trim().isEmpty) return null;
    final relative = fs.pathContext.relative(
      probe.credentialPath,
      from: toolRoot,
    );
    return CredentialFile(relativePath: relative, content: content);
  }
}

Future<CredentialActionResult> _importCursorPath(
  CursorProviderCredentialsService service, {
  required String providerId,
  required String path,
  required bool replace,
}) async {
  if (path.endsWith('auth.json')) {
    return service.importAuthJsonFile(providerId, path, replace: replace);
  }
  return service.importFromCursorDirectory(providerId, path, replace: replace);
}

final _emptyCatalogUpdates = _EmptyListenable();

final class _EmptyListenable implements Listenable {
  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}
