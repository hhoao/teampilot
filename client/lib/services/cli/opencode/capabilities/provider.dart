import 'package:flutter/foundation.dart';

import '../../../../models/app_provider_config.dart';
import '../../../../models/credential_action_result.dart';
import '../../../../models/credential_probe.dart';
import '../../../provider/credential_binding.dart';
import '../../../provider/passthrough_provider_form_capability.dart';
import '../../../io/filesystem.dart';
import '../../../remote/remote_credential_materializer.dart';
import '../../registry/capabilities/provider_capability.dart';
import '../provider/opencode_data_layout.dart';
import '../provider/opencode_effort_catalog.dart';
import '../provider/opencode_live_import.dart';
import '../provider/opencode_model_catalog.dart';
import '../provider/opencode_models_service.dart';
import '../provider/opencode_provider_credentials_service.dart';
import '../provider_presets.dart';

abstract final class OpencodeFormExtraKeys {
  static const effort = 'effort';
}

/// OpenCode model catalog from the live models.dev fetch, falling back to the
/// built-in static [OpencodeModelCatalog] (offline / first run before fetch).
final class OpencodeCatalogSource implements ModelCatalogSource {
  const OpencodeCatalogSource(this._modelsService);

  final OpencodeModelsService? _modelsService;

  @override
  List<String> modelsFor({
    required AppProviderConfig? provider,
    required String providerId,
  }) {
    final id = provider?.id ?? providerId;
    final live = _modelsService?.modelIdsFor(providerId: id) ?? const [];
    if (live.isNotEmpty) return live;
    return OpencodeModelCatalog.knownModelsForProvider(id);
  }
}

/// OpenCode provider 全栈:目录/表单/模型(实时 models.dev)/凭证/effort。
final class OpencodeProviderCapability extends CatalogModelCapability
    with PassthroughProviderFormDefaults
    implements ProviderCapability, RefreshableProviderModelCapability {
  const OpencodeProviderCapability({
    OpencodeModelsService? modelsService,
    OpencodeProviderCredentialsService? credentials,
  }) : _modelsService = modelsService,
       _credentials = credentials;

  final OpencodeModelsService? _modelsService;
  final OpencodeProviderCredentialsService? _credentials;

  OpencodeProviderCredentialsService? get _service => _credentials;

  // ---- ProviderCatalogCapability ----
  @override
  CliTool get catalogCli => CliTool.opencode;

  @override
  String? get defaultOfficialProviderId => 'opencode';

  @override
  Future<ProviderCatalogSnapshot> loadFromLiveSources(
    ProviderCatalogLoadContext context,
  ) => OpencodeLiveImport.loadSnapshot(context);

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
  List<AppProviderPreset> get presets => OpencodeProviderPresets.all;

  @override
  Map<String, Object?> defaultConfig() => const {};

  @override
  String defaultApiKeyField() => 'api_key';

  @override
  Map<String, Object?> extraFromExisting(AppProviderConfig? existing) {
    final config = existing?.config ?? defaultConfig();
    return {
      OpencodeFormExtraKeys.effort: config['reasoningEffort']?.toString() ?? '',
    };
  }

  @override
  Map<String, Object?> extraFromPreset(AppProviderPreset preset) => {
    OpencodeFormExtraKeys.effort:
        preset.template.config['reasoningEffort']?.toString() ?? '',
  };

  @override
  Map<String, Object?> buildConfig(ProviderFormInput input) {
    final config = Map<String, Object?>.from(input.config);
    final effort =
        input.extra[OpencodeFormExtraKeys.effort]?.toString().trim() ?? '';
    if (effort.isEmpty) {
      config.remove('reasoningEffort');
    } else {
      config['reasoningEffort'] = effort;
    }
    return config;
  }

  // ---- ProviderModelCapability (live models.dev) ----
  @override
  bool get supportsModelTiers => false;

  @override
  List<ModelCatalogSource> get catalogSources => [
    OpencodeCatalogSource(_modelsService),
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
    return service.ensureLoaded(forceRefresh: forceRefresh);
  }

  @override
  ProviderModelPickerMode pickerMode(AppProviderConfig provider) =>
      ProviderModelPickerMode.catalogWithCustomEntry;

  // ---- ProviderCredentialCapability ----
  @override
  bool appliesTo(AppProviderConfig provider) =>
      provider.cli == CliTool.opencode && provider.isOfficial;

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
        kind: ProviderCredentialActionKind.importFile,
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
    return switch (kind) {
      ProviderCredentialActionKind.login => service.runAuthLogin(providerId),
      ProviderCredentialActionKind.importGlobal => service.importFromGlobal(
        providerId,
        homeDirectory: input.homeDirectory?.trim() ?? '',
        replace: input.replace,
      ),
      ProviderCredentialActionKind.importFile => service.importFromFile(
        providerId,
        input.pickedPath?.trim() ?? '',
        replace: input.replace,
      ),
      ProviderCredentialActionKind.importDirectory =>
        CredentialActionResult.unsupported(),
      ProviderCredentialActionKind.revoke => service.revokeCredentials(
        providerId,
      ),
    };
  }

  @override
  bool get supportsCredentialBinding => false;

  // ---- CredentialBindingCapability (no concept: fall back to isolated) ----
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
  }) async {
    final path = OpencodeProviderCredentialsService(
      fs: fs,
      basePath: basePath,
    ).credentialPath(provider.id);
    final content = await fs.readString(path);
    if (content == null || content.trim().isEmpty) return null;
    return CredentialFile(
      relativePath: '${provider.id}/${OpencodeDataLayout.authFileName}',
      content: content,
    );
  }

  // ---- CliEffortCapability ----
  @override
  EffortPickerPlacement teamPickerPlacement() => EffortPickerPlacement.hidden;

  @override
  EffortPickerPlacement memberPickerPlacement({AppProviderConfig? provider}) =>
      EffortPickerPlacement.hidden;

  @override
  EffortPickerPlacement providerPickerPlacement(AppProviderConfig provider) =>
      EffortPickerPlacement.provider;

  @override
  bool isApplicable({required String model}) =>
      OpencodeEffortCatalog.modelSupportsEffort(model);

  @override
  List<String> effortCandidates({
    required String model,
    AppProviderConfig? provider,
  }) => OpencodeEffortCatalog.levelsForModel(model);

  @override
  String defaultEffort({required String model, AppProviderConfig? provider}) {
    final fromProvider =
        provider?.config['reasoningEffort']?.toString().trim() ?? '';
    if (fromProvider.isNotEmpty) return fromProvider;
    return OpencodeEffortCatalog.defaultLevel;
  }
}

final _emptyCatalogUpdates = _EmptyListenable();

final class _EmptyListenable implements Listenable {
  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}
