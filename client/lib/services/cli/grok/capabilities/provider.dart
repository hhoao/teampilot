import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';

import '../../../../models/app_provider_config.dart';
import '../../../../models/credential_action_result.dart';
import '../../../../models/credential_probe.dart';
import '../../../../utils/logging/logger_utils.dart';
import '../../../../widgets/home_storage_scope.dart';
import '../../../io/filesystem.dart';
import '../../../provider/credential_binding.dart';
import '../../../provider/passthrough_provider_form_capability.dart';
import '../../../chat/launch/staging/manifest/work_plane_paths.dart';
import '../../../remote/remote_credential_materializer.dart';
import '../../../storage/home_storage.dart';
import '../../registry/capabilities/acp_capability.dart';
import '../../registry/capabilities/interactive_login_capability.dart';
import '../../registry/config_profile/config_profile_context.dart';
import '../../registry/capabilities/provider_capability.dart';
import '../grok_constants.dart';
import '../grok_toml.dart';
import '../provider/grok_auth_store.dart';
import '../provider/grok_login_dialog.dart';
import '../provider/grok_provider_settings_resolver.dart';
import '../provider_presets.dart';

abstract final class GrokModelCatalog {
  const GrokModelCatalog._();

  /// Static fallback because `grok agent` advertises the live model list via
  /// ACP `configOptions`; offline / unauthenticated rows still need a picker.
  static const knownModels = <String>[
    'grok-4.7',
    'grok-4.6',
    'grok-4.5',
    'grok-4',
    'grok-code-fast-1',
  ];

  static const displayNames = <String, String>{
    'grok-4.7': 'Grok 4.7',
    'grok-4.6': 'Grok 4.6',
    'grok-4.5': 'Grok 4.5',
    'grok-4': 'Grok 4',
    'grok-code-fast-1': 'Grok Code Fast 1',
  };

  static List<String> modelsFor({
    required AppProviderConfig? provider,
    required String providerId,
  }) => knownModels;
}

final class _GrokCatalogSource implements ModelCatalogSource {
  const _GrokCatalogSource();

  @override
  List<String> modelsFor({
    required AppProviderConfig? provider,
    required String providerId,
  }) => GrokModelCatalog.modelsFor(provider: provider, providerId: providerId);
}

/// Grok provider stack.
///
/// Auth is either an xAI API key injected as `XAI_API_KEY` (never written to
/// the isolated config dir) or an OAuth `auth.json` copied from an isolated
/// `grok login` into the per-provider credential store.
final class GrokProviderCapability extends CatalogModelCapability
    with PassthroughProviderFormDefaults
    implements
        ProviderCapability,
        InteractiveCliLoginCapability,
        ModelDisplayNameCapability {
  const GrokProviderCapability({this.storage, this.fallbackCredentialSource});

  final HomeStorage? storage;

  /// App-wide xAI API key used by the ACP capability when a seat has no
  /// provider-bound credential. This only suppresses the pre-launch warning;
  /// headless provisioning still requires its own key or auth.json.
  final AcpCredentialSource? fallbackCredentialSource;

  static const defaultProviderId = GrokConstants.defaultProviderId;

  GrokAuthStore? get _authStore {
    final home = storage;
    if (home == null) return null;
    return GrokAuthStore(
      fs: home.fs,
      basePath: home.paths.basePath,
      pathContext: home.fs.pathContext,
      machineHome: home.home,
    );
  }

  @override
  CliTool get catalogCli => CliTool.grok;

  @override
  String? get defaultOfficialProviderId => defaultProviderId;

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
  bool get supportsOAuthCredentials => true;
  @override
  bool get usesLlmConfigJsonPreview => false;

  @override
  List<AppProviderPreset> get presets => GrokProviderPresets.all;

  @override
  Map<String, Object?> defaultConfig() => const {};

  @override
  String defaultApiKeyField() => 'api_key';

  @override
  bool get supportsModelTiers => false;

  @override
  List<ModelCatalogSource> get catalogSources => const [_GrokCatalogSource()];

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
  String? modelDisplayName({
    required String providerId,
    required String modelId,
  }) => GrokModelCatalog.displayNames[modelId.trim()];

  // ---- ProviderCredentialCapability (xAI account via grok login) ----
  @override
  bool appliesTo(AppProviderConfig provider) =>
      provider.isOfficial && !Platform.isAndroid && !Platform.isIOS;

  @override
  List<ProviderCredentialActionSpec> actionsFor(AppProviderConfig provider) {
    if (!appliesTo(provider)) return const [];
    return const [
      // Kept visible when ready so the user can switch accounts.
      ProviderCredentialActionSpec(
        kind: ProviderCredentialActionKind.login,
        primary: true,
        showWhenReady: true,
      ),
      ProviderCredentialActionSpec(
        kind: ProviderCredentialActionKind.importGlobal,
        showWhenReady: false,
      ),
    ];
  }

  @override
  Future<CredentialProbe> probe(AppProviderConfig provider) async {
    final store = _authStore;
    if (store == null) {
      return CredentialProbe(
        providerId: provider.id,
        status: provider.apiKey.trim().isNotEmpty
            ? CredentialStatus.ready
            : CredentialStatus.missing,
        credentialPath: '',
      );
    }
    final ready =
        provider.apiKey.trim().isNotEmpty ||
        await store.hasProviderAuth(provider.id);
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
    final store = _authStore;
    if (store == null) return CredentialActionResult.serviceUnavailable();
    if (kind == ProviderCredentialActionKind.login) {
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
    if (kind == ProviderCredentialActionKind.importGlobal) {
      final home = input.homeDirectory?.trim() ?? '';
      final importer = home.isEmpty || home == storage?.home
          ? store
          : GrokAuthStore(
              fs: store.fs,
              basePath: store.basePath,
              pathContext: store.pathContext,
              machineHome: home,
            );
      final imported = await importer.importMachineAuth(providerId);
      return imported
          ? CredentialActionResult.success
          : CredentialActionResult.failure(
              const CredentialActionFailure(
                code: CredentialActionFailureCode.verifyFailed,
              ),
            );
    }
    return CredentialActionResult.unsupported();
  }

  @override
  String get loginExecutableName => GrokConstants.executableName;

  @override
  List<String> get loginArguments => const ['login', '--device-auth'];

  @override
  Widget buildLoginDialog(
    BuildContext context, {
    required AppProviderConfig provider,
    required String executable,
  }) {
    final home = homeStorageOf(context);
    final store = GrokAuthStore(
      fs: home.fs,
      basePath: home.paths.basePath,
      pathContext: home.fs.pathContext,
      machineHome: home.home,
    );
    return GrokLoginDialog(
      executable: executable,
      arguments: loginArguments,
      store: store,
      providerId: provider.id,
    );
  }

  @override
  bool hidesApiKeyFields(AppProviderConfig provider) => false;

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

  // ---- Effort: hidden until ACP `reasoning_effort` is wired through the
  // session-home overlay. The model picker still exposes the live ACP options.
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
      CliTool.grok.value,
      memberId: ctx.scope.memberId,
    );
    await delegate.fs.ensureDir(configDir);

    final provider = await _resolveLaunchProvider(ctx);
    final model = _resolveModel(ctx, provider);
    final configPath = delegate.joinWork(
      configDir,
      GrokConstants.configFileName,
    );
    if (model.isNotEmpty) {
      await mergeGrokTomlSection(
        fs: delegate.fs,
        configPath: configPath,
        section: 'models',
        values: {'default': model},
      );
    }
    await writeGrokIsolationDefaults(delegate.fs, configPath);

    final memberProvider = ctx.member?.provider.trim() ?? '';
    final providerId =
        provider?.id.trim() ??
        (memberProvider.isEmpty ? defaultProviderId : memberProvider);
    final apiKey = provider?.apiKey.trim() ?? '';
    final warnings = <String>[];
    if (apiKey.isNotEmpty) {
      // API-key seats must not inherit a stale OAuth token: Grok's credential
      // resolution prefers a signed-in session token over `XAI_API_KEY`.
      await _removeSessionAuth(delegate, configDir);
    } else {
      final store = _authStore;
      if (store == null) {
        warnings.add('grok_auth_store_unavailable');
      } else {
        final seeded = ctx.crossMachine
            ? await _seedCrossMachineAuth(
                ctx,
                store: store,
                configDir: configDir,
                providerId: providerId,
              )
            : await store.seedSessionAuth(
                providerId: providerId,
                sessionFs: delegate.fs,
                sessionPathContext: delegate.fs.pathContext,
                sessionConfigDir: configDir,
              );
        if (!seeded) {
          final fallback = fallbackCredentialSource?.call()?.trim() ?? '';
          if (fallback.isEmpty) {
            warnings.add('grok_credentials_missing');
            AppLogger.instance.w(
              'grok: session auth.json not seeded; the session will need '
              'XAI_API_KEY or a sign-in (provider "$providerId")',
            );
          }
        }
      }
    }

    return SessionHomeContribution(
      environment: {
        GrokConstants.homeEnvKey: configDir,
        if (apiKey.isNotEmpty) GrokConstants.apiKeyEnvKey: apiKey,
      },
      warnings: warnings,
    );
  }

  /// Copies the control-plane `auth.json` onto the work plane.
  ///
  /// The overlay cannot observe a remote marker, so every cross-machine
  /// connect recopies the current source rather than trusting a stale seat.
  Future<bool> _seedCrossMachineAuth(
    SessionHomeContext ctx, {
    required GrokAuthStore store,
    required String configDir,
    required String providerId,
  }) async {
    final source = await store.authSourcePath(providerId);
    if (source == null) return false;
    final target = ctx.paths.joinWork(configDir, GrokConstants.authFileName);
    final fs = ctx.paths.fs;
    await fs.ensureDir(fs.pathContext.dirname(target));
    if (fs is OverlayFilesystem) {
      await fs.copyFilePrivate(source, target);
    } else {
      await fs.copyFile(source, target);
      store.restrictFile(target);
    }
    return true;
  }

  Future<void> _removeSessionAuth(
    ConfigProfileDelegate delegate,
    String configDir,
  ) async {
    for (final name in [
      GrokConstants.authFileName,
      GrokConstants.authMarkerFileName,
    ]) {
      final path = delegate.joinWork(configDir, name);
      if ((await delegate.fs.stat(path)).exists) {
        await delegate.fs.removeRecursive(path);
      }
    }
  }

  Future<AppProviderConfig?> _resolveLaunchProvider(
    SessionHomeContext ctx,
  ) async {
    final home = storage;
    if (home == null) return null;
    final resolver = GrokProviderSettingsResolver(
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
    return provider?.defaultModel.trim() ?? '';
  }
}

final _emptyCatalogUpdates = _EmptyListenable();

final class _EmptyListenable implements Listenable {
  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}
