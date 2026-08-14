import 'package:flutter/widgets.dart';

import '../../../../models/app_provider_config.dart';
import '../../../../models/credential_action_result.dart';
import '../../../../models/credential_probe.dart';
import '../../../provider/credential_binding.dart';
import '../../../io/filesystem.dart';
import '../../../remote/remote_credential_materializer.dart';
import '../../../storage/app_storage.dart';
import '../../registry/capabilities/provider_capability.dart';
import '../provider/claude_effort_catalog.dart';
import '../provider/claude_live_import.dart';
import '../provider/claude_model_catalog.dart';
import '../provider/claude_official_provider.dart';
import '../provider/claude_provider_credentials_service.dart';
import '../provider/claude_provider_form_section.dart';
import '../provider_presets.dart';

const _apiKeyFields = ['ANTHROPIC_AUTH_TOKEN', 'ANTHROPIC_API_KEY'];

/// Claude's built-in official aliases + frontier model ids.
final class ClaudeCatalogSource implements ModelCatalogSource {
  const ClaudeCatalogSource();

  @override
  List<String> modelsFor({
    required AppProviderConfig? provider,
    required String providerId,
  }) => ClaudeModelCatalog.knownModelsForProviderId(
    providerId,
    provider: provider,
  );
}

/// Claude provider 全栈:目录/表单/模型/凭证/effort/home 材料化。
final class ClaudeProviderCapability extends CatalogModelCapability
    implements ProviderCapability {
  const ClaudeProviderCapability({
    ClaudeProviderCredentialsService? credentials,
  }) : _credentials = credentials;

  final ClaudeProviderCredentialsService? _credentials;

  ClaudeProviderCredentialsService? get _service => _credentials;

  // ---- ProviderCatalogCapability ----
  @override
  CliTool get catalogCli => CliTool.claude;

  @override
  String? get defaultOfficialProviderId => 'claude-official';

  @override
  Future<ProviderCatalogSnapshot> loadFromLiveSources(
    ProviderCatalogLoadContext context,
  ) => ClaudeLiveImport.loadSnapshot(context);

  // ---- ProviderDisplayCapability ----
  @override
  bool get hasModelPanel => false;
  @override
  bool get showModelCount => false;
  @override
  bool get supportsDelegate => true;
  @override
  bool get supportsOAuthCredentials => true;
  @override
  bool get usesLlmConfigJsonPreview => false;

  // ---- ProviderFormCapability ----
  @override
  List<AppProviderPreset> get presets => ClaudeProviderPresets.all;

  @override
  Map<String, Object?> defaultConfig() => {'env': <String, Object?>{}};

  @override
  String defaultApiKeyField() => 'ANTHROPIC_AUTH_TOKEN';

  @override
  String normalizeApiKeyField(String? raw) {
    final value = raw?.trim() ?? '';
    return _apiKeyFields.contains(value) ? value : defaultApiKeyField();
  }

  @override
  Map<String, Object?> configForCliSwitch() => defaultConfig();

  @override
  Map<String, Object?> extraFromExisting(AppProviderConfig? existing) {
    final config = existing?.config ?? defaultConfig();
    return _extraFromConfig(config);
  }

  @override
  Map<String, Object?> extraFromPreset(AppProviderPreset preset) =>
      _extraFromConfig(preset.template.config);

  @override
  Map<String, Object?> buildConfig(ProviderFormInput input) {
    // Endpoint, credential field, and model live on the canonical top-level
    // fields (baseUrl / apiKeyField / defaultModel) and are materialized at
    // launch — the form never freezes derived env into the record here.
    return Map<String, Object?>.from(input.config);
  }

  @override
  Widget buildExtraSection(
    BuildContext context,
    ProviderFormSectionProps props,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 16),
        ClaudeProviderFormSection(
          apiKeyField: props.apiKeyField,
          onApiKeyFieldChanged: props.onApiKeyFieldChanged,
        ),
      ],
    );
  }

  Map<String, Object?> _extraFromConfig(Map<String, Object?> config) =>
      const {};

  // ---- ProviderModelCapability ----
  @override
  bool get supportsModelTiers => true;

  @override
  List<ModelCatalogSource> get catalogSources => const [ClaudeCatalogSource()];

  @override
  ProviderModelPickerMode pickerMode(AppProviderConfig provider) {
    if (provider.cli != CliTool.claude) {
      return ProviderModelPickerMode.hidden;
    }
    return ProviderModelPickerMode.catalogWithCustomEntry;
  }

  @override
  String defaultModel({
    required AppProviderConfig? provider,
    required String providerId,
  }) {
    if (provider != null && isOfficialClaudeProvider(provider)) {
      final fromProvider = provider.defaultModel.trim();
      if (fromProvider.isNotEmpty) return fromProvider;
      return ClaudeModelCatalog.defaultOfficialAlias;
    }
    return resolveDefaultProviderModel(
      this,
      provider: provider,
      providerId: providerId,
    );
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

  // ---- ProviderCredentialCapability + CredentialBindingCapability ----
  @override
  bool appliesTo(AppProviderConfig provider) =>
      isOfficialClaudeProvider(provider);

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
    final binding = resolveCredentialBinding(provider);
    return service.probe(
      provider.id,
      binding: binding,
      homeDirectory: _resolveHomeDirectory(),
    );
  }

  static String _resolveHomeDirectory() {
    if (!AppStorage.isInstalled) return '';
    try {
      return AppStorage.home;
    } on Object {
      return '';
    }
  }

  @override
  Future<CredentialActionResult> execute({
    required String providerId,
    required ProviderCredentialActionKind kind,
    ProviderCredentialActionInput input = const ProviderCredentialActionInput(),
  }) async {
    final service = _service;
    if (service == null) return CredentialActionResult.serviceUnavailable();
    final provider = input.provider;
    final binding = provider == null
        ? CredentialBindingKind.linked
        : resolveCredentialBinding(provider);
    final home = input.homeDirectory?.trim().isNotEmpty == true
        ? input.homeDirectory!.trim()
        : _resolveHomeDirectory();
    return switch (kind) {
      ProviderCredentialActionKind.login => service.runAuthLogin(
        providerId,
        binding: binding,
        homeDirectory: home,
      ),
      ProviderCredentialActionKind.importGlobal => service.importFromGlobal(
        providerId,
        homeDirectory: home,
        replace: input.replace,
        binding: binding,
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
        binding: binding,
        homeDirectory: home,
      ),
    };
  }

  @override
  bool get supportsCredentialBinding => true;

  @override
  CredentialBindingKind defaultBinding(AppProviderConfig provider) =>
      isOfficialClaudeProvider(provider)
          ? CredentialBindingKind.linked
          : CredentialBindingKind.isolated;

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
    final binding = resolveCredentialBinding(provider);
    final svc = ClaudeProviderCredentialsService(
      fs: fs,
      basePath: basePath,
      resolveHomeDirectory: () => home,
    );
    final path = svc.effectiveCredentialPath(
      provider.id,
      binding: binding,
      homeDirectory: home,
    );
    final content = await fs.readString(path);
    if (content == null || content.trim().isEmpty) return null;
    return CredentialFile(
      relativePath:
          '${provider.id}/${ClaudeProviderCredentialsService.credentialsFileName}',
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
