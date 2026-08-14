import 'package:flutter/foundation.dart';
import '../../../../models/app_provider_config.dart';
import '../../../../models/credential_action_result.dart';
import '../../../../models/credential_probe.dart';
import '../../../provider/credential_binding.dart';
import '../../../provider/passthrough_provider_form_capability.dart';
import '../../../io/filesystem.dart';
import '../../../remote/remote_credential_materializer.dart';
import '../../registry/capabilities/provider_capability.dart';
import '../provider/codex_auth_artifacts.dart';
import '../provider/codex_effort_catalog.dart';
import '../provider/codex_live_import.dart';
import '../provider/codex_official_provider.dart';
import '../provider/codex_provider_credentials_service.dart';
import '../provider_presets.dart';

abstract final class CodexFormExtraKeys {
  static const effort = 'effort';
}

/// Codex provider 全栈:目录/表单/模型/凭证/effort。
final class CodexProviderCapability extends CatalogModelCapability
    with PassthroughProviderFormDefaults
    implements ProviderCapability {
  const CodexProviderCapability({
    CodexProviderCredentialsService? credentials,
  }) : _credentials = credentials;

  final CodexProviderCredentialsService? _credentials;

  CodexProviderCredentialsService? get _service => _credentials;

  // ---- ProviderCatalogCapability ----
  @override
  CliTool get catalogCli => CliTool.codex;

  @override
  String? get defaultOfficialProviderId => 'openai-official';

  @override
  Future<ProviderCatalogSnapshot> loadFromLiveSources(
    ProviderCatalogLoadContext context,
  ) => CodexLiveImport.loadSnapshot(context);

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
  List<AppProviderPreset> get presets => CodexProviderPresets.all;

  @override
  Map<String, Object?> defaultConfig() => {'auth': <String, Object?>{}};

  @override
  String defaultApiKeyField() => 'OPENAI_API_KEY';

  @override
  Map<String, Object?> extraFromExisting(AppProviderConfig? existing) {
    final config = existing?.config ?? defaultConfig();
    return {
      CodexFormExtraKeys.effort:
          config['model_reasoning_effort']?.toString() ?? '',
    };
  }

  @override
  Map<String, Object?> extraFromPreset(AppProviderPreset preset) => {
    CodexFormExtraKeys.effort:
        preset.template.config['model_reasoning_effort']?.toString() ?? '',
  };

  @override
  Map<String, Object?> buildConfig(ProviderFormInput input) {
    final config = Map<String, Object?>.from(input.config);
    final effort =
        input.extra[CodexFormExtraKeys.effort]?.toString().trim() ?? '';
    if (effort.isEmpty) {
      config.remove('model_reasoning_effort');
    } else {
      config['model_reasoning_effort'] = effort;
    }
    return config;
  }

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

  // ---- ProviderCredentialCapability ----
  @override
  bool appliesTo(AppProviderConfig provider) =>
      isOfficialCodexOAuthProvider(provider);

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
    final path = CodexProviderCredentialsService(
      fs: fs,
      basePath: basePath,
    ).credentialPath(provider.id);
    final content = await fs.readString(path);
    if (content == null || content.trim().isEmpty) return null;
    return CredentialFile(
      relativePath: '${provider.id}/${CodexAuthArtifacts.authFileName}',
      content: content,
    );
  }

  // ---- CliEffortCapability ----
  @override
  EffortPickerPlacement teamPickerPlacement() => EffortPickerPlacement.team;

  @override
  EffortPickerPlacement memberPickerPlacement({AppProviderConfig? provider}) =>
      EffortPickerPlacement.member;

  @override
  EffortPickerPlacement providerPickerPlacement(AppProviderConfig provider) =>
      EffortPickerPlacement.provider;

  @override
  bool isApplicable({required String model}) =>
      CodexEffortCatalog.modelSupportsEffort(model);

  @override
  List<String> effortCandidates({
    required String model,
    AppProviderConfig? provider,
  }) => CodexEffortCatalog.levelsForModel(model);

  @override
  String defaultEffort({required String model, AppProviderConfig? provider}) {
    final fromProvider =
        provider?.config['model_reasoning_effort']?.toString().trim() ?? '';
    if (fromProvider.isNotEmpty) return fromProvider;
    return CodexEffortCatalog.defaultLevel;
  }
}


final _emptyCatalogUpdates = _EmptyListenable();

final class _EmptyListenable implements Listenable {
  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}
