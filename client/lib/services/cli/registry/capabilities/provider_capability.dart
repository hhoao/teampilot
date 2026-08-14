import 'package:flutter/widgets.dart';

import '../../../../models/app_provider_config.dart';
import '../../../../models/credential_action_result.dart';
import '../../../../models/credential_probe.dart';
import '../../../io/filesystem.dart';
import '../../../provider/credential_binding.dart';
import '../../../remote/remote_credential_materializer.dart';
import 'provider_catalog_capability.dart';
import 'provider_credential_capability.dart';
import 'provider_form_capability.dart';
import 'provider_model_capability.dart';
import 'cli_effort_capability.dart';
import '../cli_capability.dart';

export 'provider_catalog_capability.dart'
    show ProviderCatalogSnapshot, ProviderCatalogLoadContext;
export 'provider_credential_capability.dart'
    show
        ProviderCredentialActionKind,
        ProviderCredentialActionSpec,
        ProviderCredentialActionInput;
export 'provider_form_capability.dart'
    show ProviderFormInput, ProviderFormSectionProps;
export 'provider_model_capability.dart'
    show
        ProviderModelPickerMode,
        ProviderModelTier,
        backgroundModelFromProvider,
        mergeProviderModelCandidates,
        modelsDeclaredOnProvider,
        providerModelCount,
        resolveDefaultProviderModel,
        ModelCatalogSource,
        CatalogModelCapability,
        ProviderRecordModelCapability;
export 'cli_effort_capability.dart'
    show
        EffortPickerPlacement,
        EffortResolveContext,
        resolveContextModel,
        resolveLaunchEffort;

/// ProviderHub 契约:该 CLI 的 provider 目录、表单、模型、凭证、effort。
///
/// 一个 CLI 一个实现;consumer 用 `registry.capability<ProviderCapability>(cli)`
/// 查询,不再散落 `if (cli == …)` 分支。
abstract interface class ProviderCapability implements CliCapability {
  // ---- ProviderCatalogCapability ----
  CliTool get catalogCli;

  /// Preferred official catalog id used when a Simple launch provider is unset.
  /// Null when the CLI has no official catalog row (flashskyai).
  String? get defaultOfficialProviderId;

  /// Scans the user's global CLI install for importable provider rows.
  Future<ProviderCatalogSnapshot> loadFromLiveSources(
    ProviderCatalogLoadContext context,
  );

  // ---- ProviderDisplayCapability ----
  bool get hasModelPanel;
  bool get showModelCount;
  bool get supportsDelegate;
  bool get supportsOAuthCredentials;
  bool get usesLlmConfigJsonPreview;

  // ---- ProviderFormCapability ----
  List<AppProviderPreset> get presets;
  Map<String, Object?> defaultConfig();
  String defaultApiKeyField();
  String normalizeApiKeyField(String? raw);
  Map<String, Object?> configForCliSwitch();
  Map<String, Object?> extraFromExisting(AppProviderConfig? existing);
  Map<String, Object?> extraFromPreset(AppProviderPreset preset);
  Map<String, Object?> buildConfig(ProviderFormInput input);
  Widget buildExtraSection(BuildContext context, ProviderFormSectionProps props);

  // ---- ProviderModelCapability(+Refreshable) ----
  ProviderModelPickerMode pickerMode(AppProviderConfig provider);
  List<String> modelCandidates({
    required AppProviderConfig? provider,
    required String providerId,
    required String currentModel,
  });
  String defaultModel({
    required AppProviderConfig? provider,
    required String providerId,
  });
  bool get supportsModelTiers;

  /// Live catalog change notifications; no-op for non-refreshable CLIs.
  Listenable get catalogUpdates => _emptyCatalogUpdates;

  /// Refreshes the live model catalog; no-op for non-refreshable CLIs.
  Future<void> refreshModelCatalog({
    required String providerId,
    String? executable,
    bool forceRefresh = false,
  }) async {}

  // ---- ProviderCredentialCapability + CredentialBindingCapability ----
  /// Whether [provider] participates in credential concepts (OAuth actions or
  /// link/isolated binding) for this CLI.
  bool appliesTo(AppProviderConfig provider);
  List<ProviderCredentialActionSpec> actionsFor(AppProviderConfig provider);
  Future<CredentialProbe> probe(AppProviderConfig provider);
  Future<CredentialActionResult> execute({
    required String providerId,
    required ProviderCredentialActionKind kind,
    ProviderCredentialActionInput input = const ProviderCredentialActionInput(),
  });
  bool hidesApiKeyFields(AppProviderConfig provider);
  CredentialBindingKind defaultBinding(AppProviderConfig provider);
  Map<String, Object?> withBinding(
    Map<String, Object?> config,
    CredentialBindingKind binding,
  );

  // ---- CredentialExportCapability ----
  Future<CredentialFile?> exportCredential({
    required Filesystem fs,
    required String basePath,
    required String home,
    required AppProviderConfig provider,
  });

  // ---- CliEffortCapability ----
  EffortPickerPlacement teamPickerPlacement();
  EffortPickerPlacement memberPickerPlacement({AppProviderConfig? provider});
  EffortPickerPlacement providerPickerPlacement(AppProviderConfig provider);
  bool isApplicable({required String model});
  List<String> effortCandidates({
    required String model,
    AppProviderConfig? provider,
  });
  String defaultEffort({required String model, AppProviderConfig? provider});
}

final _emptyCatalogUpdates = _EmptyListenable();

final class _EmptyListenable implements Listenable {
  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}
