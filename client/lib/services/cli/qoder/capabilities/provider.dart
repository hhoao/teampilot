import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';

import '../../../../models/app_provider_config.dart';
import '../../../../models/credential_action_result.dart';
import '../../../../models/credential_probe.dart';
import '../../../../models/team_config.dart';
import '../../../../utils/logging/logger_utils.dart';
import '../../../../utils/team/team_member_naming.dart';
import '../../../../widgets/home_storage_scope.dart';
import '../../../chat/launch/staging/manifest/work_plane_paths.dart';
import '../../../io/filesystem.dart';
import '../../../provider/credential_binding.dart';
import '../../../provider/passthrough_provider_form_capability.dart';
import '../../../remote/remote_credential_materializer.dart';
import '../../../storage/home_storage.dart';
import '../../registry/capabilities/interactive_login_capability.dart';
import '../../registry/capabilities/provider_capability.dart';
import '../provider/qoder_auth_store.dart';
import '../provider/qoder_login_dialog.dart';
import '../provider/qoder_provider_settings_resolver.dart';
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
      machineHome: home.home,
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
    final store = _authStore;
    if (store == null) {
      return CredentialProbe(
        providerId: provider.id,
        status: CredentialStatus.missing,
        credentialPath: '',
      );
    }
    final ready = await store.hasProviderAuth(provider.id);
    final path = store.providerAuthDir(provider.id);
    final stat = await store.fs.stat(path);
    return CredentialProbe(
      providerId: provider.id,
      status: ready ? CredentialStatus.ready : CredentialStatus.missing,
      credentialPath: path,
      updatedAt: stat.isDirectory ? stat.mtime : null,
    );
  }

  @override
  Future<CredentialActionResult> execute({
    required String providerId,
    required ProviderCredentialActionKind kind,
    ProviderCredentialActionInput input = const ProviderCredentialActionInput(),
  }) async {
    if (kind != ProviderCredentialActionKind.login) {
      return CredentialActionResult.unsupported();
    }
    final store = _authStore;
    if (store == null) return CredentialActionResult.serviceUnavailable();
    final written = await store.writeProviderAuthFromLogin(
      providerId,
      loginConfigDir: store.loginConfigDir(providerId),
    );
    return written
        ? CredentialActionResult.success
        : CredentialActionResult.failure(
            const CredentialActionFailure(
              code: CredentialActionFailureCode.verifyFailed,
            ),
          );
  }

  @override
  String get loginExecutableName => 'qodercli';

  @override
  List<String> get loginArguments => const ['login'];

  @override
  Widget buildLoginDialog(
    BuildContext context, {
    required AppProviderConfig provider,
    required String executable,
  }) {
    final storage = homeStorageOf(context);
    final store = QoderAuthStore(
      fs: storage.fs,
      basePath: storage.paths.basePath,
      pathContext: storage.fs.pathContext,
    );
    return QoderLoginDialog(
      executable: executable,
      arguments: loginArguments,
      store: store,
      providerId: provider.id,
    );
  }

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
    // Resolve first: a seat bound only by the team default must seed that
    // account, not fall back to the machine login.
    final provider = await _resolveLaunchProvider(ctx);
    final providerId = provider?.id.trim() ?? ctx.member?.provider.trim() ?? '';
    final authStore = _authStore;
    if (authStore == null) {
      AppLogger.instance.w(
        'qoder: auth store unavailable; session .auth not seeded '
        '(provider "$providerId")',
      );
    } else {
      final seeded = ctx.crossMachine
          ? await _seedCrossMachineAuth(
              ctx,
              store: authStore,
              configDir: configDir,
              providerId: providerId,
            )
          : await authStore.seedSessionAuth(
              providerId: providerId,
              sessionConfigDir: configDir,
            );
      if (!seeded) {
        AppLogger.instance.w(
          'qoder: session .auth not seeded; the session will need a sign-in '
          '(provider "$providerId")',
        );
      }
    }
    final environment = <String, String>{configDirEnvKey: configDir};

    final settingsPath = delegate.joinWork(configDir, 'settings.json');
    final settings = await delegate.readSettingsFile(settingsPath);
    final denyTools = _mixedNativeTeamDenyTools(ctx);
    if (denyTools.isNotEmpty) _mergePermissionsDeny(settings, denyTools);

    final model = _resolveModel(ctx, provider);
    if (model.isNotEmpty) settings['model'] = model;
    final effort = provider?.config['reasoningEffort']?.toString().trim() ?? '';
    if (effort.isNotEmpty) settings['reasoningEffort'] = effort;

    await delegate.writeSettingsFile(
      settingsPath,
      settings,
      tool: CliTool.qoder.value,
      teamId: ctx.team?.id,
      workspaceId: ctx.workspaceId,
    );
    return SessionHomeContribution(environment: environment);
  }

  /// Copies `<source>/.auth/{user,machine_id}` onto the work plane.
  ///
  /// Reads stay on the control plane ([QoderAuthStore.authSourceDir]); the
  /// writes go through the work-plane fs so the manifest flushes them to the
  /// SSH seat. Overlay reads fall through to the control plane, so a remote
  /// marker/keep check is not observable — every connect re-copies the current
  /// control-plane source.
  Future<bool> _seedCrossMachineAuth(
    SessionHomeContext ctx, {
    required QoderAuthStore store,
    required String configDir,
    required String providerId,
  }) async {
    final source = await store.authSourceDir(providerId);
    if (source == null) return false;
    final targetDir = ctx.paths.joinWork(configDir, '.auth');
    final fs = ctx.paths.fs;
    await ensureWorkDir(fs, targetDir);
    for (final name in const [
      QoderAuthStore.userFileName,
      QoderAuthStore.machineIdFileName,
    ]) {
      final from = store.pathContext.join(source, name);
      final to = ctx.paths.joinWork(targetDir, name);
      if (fs is OverlayFilesystem) {
        // Staged into the tar with mode 0600.
        await fs.copyFilePrivate(from, to);
      } else {
        await fs.copyFile(from, to);
        store.restrictFile(to);
      }
    }
    return true;
  }

  Future<AppProviderConfig?> _resolveLaunchProvider(
    SessionHomeContext ctx,
  ) async {
    final home = storage;
    if (home == null) return null;
    final resolver = QoderProviderSettingsResolver(
      basePath: ctx.catalog.basePath,
      fs: ctx.catalog.fs,
      storage: home,
    );
    final team = ctx.team;
    if (team != null) {
      return resolver.resolveForLaunch(team: team, member: ctx.member);
    }
    final fromMember = ctx.member?.provider.trim() ?? '';
    if (fromMember.isNotEmpty) {
      final byId = await resolver.findById(fromMember);
      if (byId != null) return byId;
    }
    final resolved = ctx.resolvedProviderId?.trim() ?? '';
    if (resolved.isNotEmpty) {
      final byId = await resolver.findById(resolved);
      if (byId != null) return byId;
    }
    final official = await resolver.findById(defaultOfficialProviderId);
    return official ?? resolver.resolveSole();
  }

  String _resolveModel(SessionHomeContext ctx, AppProviderConfig? provider) {
    final fromMember = ctx.member?.model.trim() ?? '';
    if (fromMember.isNotEmpty) return fromMember;
    // No model chosen anywhere → leave settings.model untouched so the CLI's
    // own account default applies.
    return provider?.defaultModel.trim() ?? '';
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
