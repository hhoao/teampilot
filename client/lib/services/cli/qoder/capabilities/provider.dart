import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';

import '../../../../models/app_provider_config.dart';
import '../../../../models/credential_action_result.dart';
import '../../../../models/credential_probe.dart';
import '../../../../models/team_config.dart';
import '../../../../utils/team/team_member_naming.dart';
import '../../../chat/launch/staging/manifest/work_plane_paths.dart';
import '../../../io/filesystem.dart';
import '../../../provider/credential_binding.dart';
import '../../../provider/passthrough_provider_form_capability.dart';
import '../../../remote/remote_credential_materializer.dart';
import '../../../storage/home_storage.dart';
import '../../registry/capabilities/interactive_login_capability.dart';
import '../../registry/capabilities/provider_capability.dart';
import '../provider/qoder_auth_store.dart';
import '../provider_presets.dart';
import 'defaults.dart';

abstract final class QoderModelCatalog {
  const QoderModelCatalog._();

  static const knownModels = <String>[
    'auto',
    'qwen3.8-max',
    'qwen3.8-flash',
    'kimi-k3.1-pro',
    'glm-5.3',
    'deepseek-v4-pro',
    'minimax-m3.1-flash',
  ];

  static List<String> modelsFor({
    required AppProviderConfig? provider,
    required String providerId,
  }) => knownModels;
}

final class _QoderCatalogSource implements ModelCatalogSource {
  const _QoderCatalogSource();

  @override
  List<String> modelsFor({
    required AppProviderConfig? provider,
    required String providerId,
  }) => QoderModelCatalog.modelsFor(provider: provider, providerId: providerId);
}

/// Qoder provider stack: `settings.json` in the isolated `QODER_CONFIG_DIR`.
/// v1 is account-only — no API key, no OpenAI-compatible endpoint.
final class QoderProviderCapability extends CatalogModelCapability
    with PassthroughProviderFormDefaults
    implements ProviderCapability, InteractiveCliLoginCapability {
  const QoderProviderCapability({this.storage});

  final HomeStorage? storage;

  QoderAuthStore? get _authStore {
    final home = storage;
    if (home == null) return null;
    return QoderAuthStore(
      fs: home.fs,
      basePath: home.paths.basePath,
      pathContext: home.fs.pathContext,
    );
  }

  static const configDirEnvKey = 'QODER_CONFIG_DIR';

  @override
  CliTool get catalogCli => CliTool.qoder;

  @override
  String? get defaultOfficialProviderId => 'qoder';

  @override
  Future<ProviderCatalogSnapshot> loadFromLiveSources(
    ProviderCatalogLoadContext context,
  ) async => const ProviderCatalogSnapshot();

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

  @override
  List<AppProviderPreset> get presets => QoderProviderPresets.all;

  @override
  Map<String, Object?> defaultConfig() => const {};

  @override
  String defaultApiKeyField() => 'api_key';

  @override
  bool get supportsModelTiers => false;

  @override
  List<ModelCatalogSource> get catalogSources => const [_QoderCatalogSource()];

  @override
  ProviderModelPickerMode pickerMode(AppProviderConfig provider) =>
      ProviderModelPickerMode.catalogWithCustomEntry;

  @override
  Listenable get catalogUpdates => _emptyCatalogUpdates;

  @override
  Future<void> refreshModelCatalog({
    required String providerId,
    AppProviderConfig? provider,
    String? executable,
    bool forceRefresh = false,
  }) async {}

  @override
  bool appliesTo(AppProviderConfig provider) =>
      provider.isOfficial && !Platform.isAndroid && !Platform.isIOS;

  @override
  List<ProviderCredentialActionSpec> actionsFor(AppProviderConfig provider) {
    if (!appliesTo(provider)) return const [];
    return const [
      ProviderCredentialActionSpec(
        kind: ProviderCredentialActionKind.login,
        primary: true,
        showWhenReady: true,
      ),
    ];
  }

  @override
  Future<CredentialProbe> probe(AppProviderConfig provider) async {
    return CredentialProbe(
      providerId: provider.id,
      status: CredentialStatus.missing,
      credentialPath: '',
    );
  }

  @override
  Future<CredentialActionResult> execute({
    required String providerId,
    required ProviderCredentialActionKind kind,
    ProviderCredentialActionInput input = const ProviderCredentialActionInput(),
  }) async => CredentialActionResult.unsupported();

  @override
  String get loginExecutableName => 'qodercli';

  @override
  List<String> get loginArguments => const ['login'];

  @override
  Widget buildLoginDialog(
    BuildContext context, {
    required AppProviderConfig provider,
    required String executable,
  }) => const SizedBox.shrink();

  @override
  bool hidesApiKeyFields(AppProviderConfig provider) =>
      provider.isOfficial && !Platform.isAndroid && !Platform.isIOS;

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

  @override
  Future<CredentialFile?> exportCredential({
    required Filesystem fs,
    required String basePath,
    required String home,
    required AppProviderConfig provider,
  }) async => null;

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

  @override
  Future<SessionHomeContribution> materializeSessionHome(
    SessionHomeContext ctx,
  ) async {
    final delegate = ctx.paths;
    final configDir = delegate.sessionToolDir(
      ctx.scope.workspaceId,
      ctx.scope.sessionId,
      CliTool.qoder.value,
      memberId: ctx.scope.memberId,
    );
    await delegate.fs.ensureDir(configDir);
    final providerId = ctx.member?.provider.trim() ?? '';
    await _authStore?.seedSessionAuth(
      providerId: providerId,
      sessionConfigDir: configDir,
    );
    final environment = <String, String>{configDirEnvKey: configDir};

    final settingsPath = delegate.joinWork(configDir, 'settings.json');
    final settings = await delegate.readSettingsFile(settingsPath);
    final denyTools = _mixedNativeTeamDenyTools(ctx);
    if (denyTools.isNotEmpty) _mergePermissionsDeny(settings, denyTools);

    final model = ctx.member?.model.trim() ?? '';
    if (model.isNotEmpty) settings['model'] = model;
    await delegate.writeSettingsFile(
      settingsPath,
      settings,
      tool: CliTool.qoder.value,
      teamId: ctx.team?.id,
      workspaceId: ctx.workspaceId,
    );
    return SessionHomeContribution(environment: environment);
  }
}

List<String> _mixedNativeTeamDenyTools(SessionHomeContext ctx) {
  if (ctx.isSimple || ctx.team?.teamMode != TeamMode.mixed) return const [];
  final member = ctx.member;
  return mixedDenyToolsForQoder(
    isLead: member != null && TeamMemberNaming.isTeamLead(member),
  );
}

void _mergePermissionsDeny(
  Map<String, Object?> settings,
  List<String> denyTools,
) {
  final current = settings['permissions'];
  final permissions = current is Map
      ? Map<String, Object?>.from(current)
      : <String, Object?>{};
  final existing = permissions['deny'];
  permissions['deny'] = <String>{
    if (existing is List) ...existing.whereType<String>(),
    ...denyTools,
  }.toList(growable: false);
  settings['permissions'] = permissions;
}

final _emptyCatalogUpdates = _EmptyListenable();

final class _EmptyListenable implements Listenable {
  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}
