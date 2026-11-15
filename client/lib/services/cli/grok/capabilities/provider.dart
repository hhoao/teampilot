import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';

import '../../../../models/app_provider_config.dart';
import '../../../../models/credential_action_result.dart';
import '../../../../models/credential_lease.dart';
import '../../../../models/credential_probe.dart';
import '../../../../widgets/home_storage_scope.dart';
import '../../../io/filesystem.dart';
import '../../../provider/credential_binding.dart';
import '../../../provider/oauth_credential_authority.dart';
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
import '../provider/grok_credential_adapter.dart';
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
/// the isolated config dir) or an OAuth sign-in owned by
/// [OAuthCredentialAuthority]. OAuth seats receive no token on disk; the
/// per-seat shim requested by [GrokCredentialAdapter] mints a short-lived
/// lease from the control plane.
final class GrokProviderCapability extends CatalogModelCapability
    with PassthroughProviderFormDefaults
    implements
        ProviderCapability,
        InteractiveCliLoginCapability,
        ModelDisplayNameCapability {
  const GrokProviderCapability({
    this.storage,
    this.fallbackCredentialSource,
    this.authority,
    this.adapter,
  });

  final HomeStorage? storage;

  /// App-wide xAI API key used by the ACP capability when a seat has no
  /// provider-bound credential. This only suppresses the pre-launch warning;
  /// headless provisioning still requires its own key or a lease.
  final AcpCredentialSource? fallbackCredentialSource;

  /// Control-plane single owner of the xAI refresh token.
  final OAuthCredentialAuthority? authority;

  /// Injects the lease shim into the session home.
  final GrokCredentialAdapter? adapter;

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
    // The Authority, not the presence of a legacy auth.json, owns readiness.
    // `expiring` means the access token is stale but the RT can still mint a
    // lease, so it must not read as "needs sign-in".
    final health = provider.apiKey.trim().isNotEmpty
        ? CredentialHealth.ready
        : authority == null
        ? CredentialHealth.missing
        : await authority!.status(provider.id);
    final ready =
        health != CredentialHealth.missing &&
        health != CredentialHealth.rejected;
    final path = _authStore?.providerAuthDir(provider.id) ?? '';
    final stat = path.isEmpty ? null : await _authStore!.fs.stat(path);
    return CredentialProbe(
      providerId: provider.id,
      status: ready ? CredentialStatus.ready : CredentialStatus.missing,
      credentialPath: path,
      updatedAt: stat != null && stat.isDirectory ? stat.mtime : null,
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
    final target = authority;
    if (kind == ProviderCredentialActionKind.login) {
      if (target == null) return CredentialActionResult.serviceUnavailable();
      final bytes = await store.fs.readBytes(store.loginAuthPath(providerId));
      if (bytes == null || bytes.isEmpty) {
        return CredentialActionResult.failure(
          const CredentialActionFailure(
            code: CredentialActionFailureCode.verifyFailed,
          ),
        );
      }
      return await target.importFromLogin(providerId, bytes)
          ? CredentialActionResult.success
          : CredentialActionResult.failure(
              const CredentialActionFailure(
                code: CredentialActionFailureCode.verifyFailed,
              ),
            );
    }
    if (kind == ProviderCredentialActionKind.importGlobal) {
      if (target == null) return CredentialActionResult.serviceUnavailable();
      final home = input.homeDirectory?.trim() ?? '';
      final importer = home.isEmpty || home == storage?.home
          ? store
          : GrokAuthStore(
              fs: store.fs,
              basePath: store.basePath,
              pathContext: store.pathContext,
              machineHome: home,
            );
      final bytes = await store.fs.readBytes(importer.machineAuthPath);
      if (bytes == null || bytes.isEmpty) {
        return CredentialActionResult.failure(
          const CredentialActionFailure(
            code: CredentialActionFailureCode.verifyFailed,
          ),
        );
      }
      return await target.importFromLogin(providerId, bytes)
          ? CredentialActionResult.success
          : CredentialActionResult.failure(
              const CredentialActionFailure(
                code: CredentialActionFailureCode.verifyFailed,
              ),
            );
    }
    if (kind == ProviderCredentialActionKind.revoke) {
      if (target == null) return CredentialActionResult.serviceUnavailable();
      await target.revoke(providerId);
      return CredentialActionResult.success;
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
    // Must equal GrokCredentialAdapter's session-home dir: the adapter returns
    // `GROK_HOME` from its own computation, and config.toml written anywhere
    // else would be invisible to the agent.
    final configDir = delegate.sessionToolDir(
      ctx.scope.workspaceId,
      ctx.scope.sessionId,
      CliTool.grok.value,
      memberId: ctx.memberId ?? ctx.scope.memberId,
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
    final environment = <String, String>{
      GrokConstants.homeEnvKey: configDir,
      if (apiKey.isNotEmpty) GrokConstants.apiKeyEnvKey: apiKey,
    };
    // A new seat must not inherit a token from an earlier launch of the same
    // config dir: grok prefers a signed-in session token over `XAI_API_KEY`,
    // and an OAuth seat must resolve auth from the current lease only.
    await _removeSessionAuth(delegate, configDir);
    if (apiKey.isEmpty) {
      final grokAdapter = adapter;
      if (grokAdapter == null) {
        warnings.add('grok_credentials_missing');
      } else {
        try {
          final leaseContribution = await grokAdapter.materialize(
            ctx,
            providerId: providerId,
          );
          for (final entry in leaseContribution.environment.entries) {
            environment[entry.key] = entry.value;
          }
        } on CredentialUnavailableException catch (error) {
          // Stage 1 pre-launch gate: fail before spawning an agent that would
          // immediately report "not logged in".
          throw GrokCredentialUnavailableException(providerId, error.health);
        }
      }
    }

    return SessionHomeContribution(
      environment: environment,
      warnings: warnings,
    );
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

/// Launch-time failure: the seat's provider has no usable credential, so an
/// agent must not be spawned. Propagates through `materializeSessionHome` as a
/// session-connect failure; [health] drives the "needs sign-in" row.
final class GrokCredentialUnavailableException implements Exception {
  const GrokCredentialUnavailableException(this.providerId, this.health);

  final String providerId;
  final CredentialHealth health;

  @override
  String toString() =>
      'Grok provider $providerId needs a sign-in (${health.name})';
}

final class _EmptyListenable implements Listenable {
  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}
