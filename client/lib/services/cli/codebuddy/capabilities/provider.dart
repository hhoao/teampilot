import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../../../models/app_provider_config.dart';
import '../../../../models/credential_action_result.dart';
import '../../../../models/credential_probe.dart';
import '../../../../widgets/home_storage_scope.dart';
import '../../../chat/launch/staging/manifest/work_plane_paths.dart';
import '../../../io/filesystem.dart';
import '../../../provider/credential_binding.dart';
import '../../../provider/passthrough_provider_form_capability.dart';
import '../../../remote/remote_credential_materializer.dart';
import '../../../storage/home_storage.dart';
import '../../registry/capabilities/interactive_login_capability.dart';
import '../../registry/capabilities/provider_capability.dart';
import '../provider/codebuddy_auth_store.dart';
import '../provider/codebuddy_login_dialog.dart';
import '../provider/codebuddy_provider_settings_resolver.dart';
import '../provider_presets.dart';

/// Built-in CodeBuddy model ids (the CLI's own account catalog;
/// picker also accepts a custom entry, so this list is a convenience only).
abstract final class CodebuddyModelCatalog {
  const CodebuddyModelCatalog._();

  static const knownModels = <String>[
    'hy4-preview',
    'hy3',
    'hy3-x',
    'deepseek-v4.1-flash',
    'deepseek-v4-pro',
    'glm-5.3',
    'glm-5.2',
    'kimi-k3.1-pro',
    'minimax-m3',
    'step-5-preview',
  ];

  /// Models that expose reasoning-effort levels in the CLI's `session/new`
  /// model metadata.
  static const reasoningModels = <String>{'hy4-preview', 'hy3', 'hy3-x'};

  static List<String> modelsFor({
    required AppProviderConfig? provider,
    required String providerId,
  }) => knownModels;
}

final class _CodebuddyCatalogSource implements ModelCatalogSource {
  const _CodebuddyCatalogSource();

  @override
  List<String> modelsFor({
    required AppProviderConfig? provider,
    required String providerId,
  }) => CodebuddyModelCatalog.modelsFor(
    provider: provider,
    providerId: providerId,
  );
}

/// CodeBuddy provider stack: models.json + settings.json in the
/// isolated `CODEBUDDY_CONFIG_DIR`, API key supplied through the process env
/// (`CODEBUDDY_API_KEY`) so it never lands on disk.
final class CodebuddyProviderCapability extends CatalogModelCapability
    with PassthroughProviderFormDefaults
    implements ProviderCapability, InteractiveCliLoginCapability {
  const CodebuddyProviderCapability({this.storage});

  /// Home control-plane storage injected at registry construction; required to
  /// read the provider catalog while materializing a session home.
  final HomeStorage? storage;

  static const configDirEnvKey = 'CODEBUDDY_CONFIG_DIR';

  // ---- ProviderCatalogCapability ----
  @override
  CliTool get catalogCli => CliTool.codebuddy;

  @override
  String? get defaultOfficialProviderId => 'codebuddy';

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
  List<AppProviderPreset> get presets => CodebuddyProviderPresets.all;

  @override
  Map<String, Object?> defaultConfig() => const {};

  @override
  String defaultApiKeyField() => 'api_key';

  @override
  bool get supportsModelTiers => false;

  @override
  List<ModelCatalogSource> get catalogSources => const [
    _CodebuddyCatalogSource(),
  ];

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

  // ---- ProviderCredentialCapability (isolated login + interactive TUI) ----
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
    final auth = await store.readProviderAuth(provider.id);
    final token = store.accessTokenFor(auth);
    final path = store.providerAuthPath(provider.id);
    final stat = await store.fs.stat(path);
    final ready = token != null || provider.apiKey.trim().isNotEmpty;
    return CredentialProbe(
      providerId: provider.id,
      status: ready ? CredentialStatus.ready : CredentialStatus.missing,
      credentialPath: path,
      updatedAt: stat.isFile ? stat.mtime : null,
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
    if (store == null) {
      return CredentialActionResult.serviceUnavailable();
    }
    final login = await store.readLoginAuth(providerId);
    if (login == null) {
      return CredentialActionResult.failure(
        const CredentialActionFailure(
          code: CredentialActionFailureCode.verifyFailed,
        ),
      );
    }
    final written = await store.writeProviderAuth(providerId, login);
    return written
        ? CredentialActionResult.success
        : CredentialActionResult.failure(
            const CredentialActionFailure(
              code: CredentialActionFailureCode.verifyFailed,
            ),
          );
  }

  /// The CLI's TUI owns the login flow; there is no headless login command.
  @override
  String get loginExecutableName => 'codebuddy';

  @override
  List<String> get loginArguments => const [];

  @override
  Widget buildLoginDialog(
    BuildContext context, {
    required AppProviderConfig provider,
    required String executable,
  }) {
    final storage = homeStorageOf(context);
    final store = CodebuddyAuthStore(
      fs: storage.fs,
      basePath: storage.paths.basePath,
      pathContext: storage.fs.pathContext,
    );
    return CodebuddyLoginDialog(
      executable: executable,
      arguments: loginArguments,
      store: store,
      providerId: provider.id,
    );
  }

  CodebuddyAuthStore? get _authStore {
    final home = storage;
    if (home == null) return null;
    return CodebuddyAuthStore(
      fs: home.fs,
      basePath: home.paths.basePath,
      pathContext: home.fs.pathContext,
    );
  }

  /// Injects the provider's isolated access token into a session home.
  Future<String?> _providerAccessToken(String providerId) async {
    final store = _authStore;
    if (store == null) return null;
    return store.accessTokenFor(await store.readProviderAuth(providerId));
  }

  @override
  bool hidesApiKeyFields(AppProviderConfig provider) =>
      provider.isOfficial && !Platform.isAndroid && !Platform.isIOS;

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
  bool isApplicable({required String model}) =>
      CodebuddyModelCatalog.reasoningModels.contains(model.trim());

  @override
  List<String> effortCandidates({
    required String model,
    AppProviderConfig? provider,
  }) {
    if (!isApplicable(model: model)) return const [];
    if (model.trim() == 'hy4-preview') return const ['high'];
    return const ['low', 'medium', 'high', 'xhigh'];
  }

  @override
  String defaultEffort({required String model, AppProviderConfig? provider}) {
    final candidates = effortCandidates(model: model, provider: provider);
    return candidates.isEmpty ? '' : candidates.last;
  }

  // ---- Session-home materialization ----
  @override
  Future<SessionHomeContribution> materializeSessionHome(
    SessionHomeContext ctx,
  ) async {
    final delegate = ctx.paths;
    final configDir = delegate.sessionToolDir(
      ctx.scope.workspaceId,
      ctx.scope.sessionId,
      CliTool.codebuddy.value,
      memberId: ctx.scope.memberId,
    );
    await delegate.fs.ensureDir(configDir);

    final environment = <String, String>{configDirEnvKey: configDir};
    final provider = await _resolveLaunchProvider(ctx);
    if (provider == null) {
      return SessionHomeContribution(environment: environment);
    }

    final accessToken = await _providerAccessToken(provider.id);
    if (accessToken != null) {
      environment[CodebuddyAuthStore.apiKeyEnvKey] = accessToken;
    }

    final settingsPath = delegate.joinWork(configDir, 'settings.json');
    final settings = await delegate.readSettingsFile(settingsPath);

    final model = _resolveModel(ctx, provider);
    if (model.isNotEmpty) {
      settings['model'] = model;
    }
    final effort = _resolveEffort(provider, model);
    if (effort.isNotEmpty) {
      settings['reasoningEffort'] = effort;
    }

    await delegate.writeSettingsFile(
      settingsPath,
      settings,
      tool: CliTool.codebuddy.value,
      teamId: ctx.team?.id,
      workspaceId: ctx.workspaceId,
    );

    final apiKey = provider.apiKey.trim();
    if (apiKey.isNotEmpty) {
      environment['CODEBUDDY_API_KEY'] = apiKey;
    }
    final baseUrl = provider.baseUrl.trim();
    if (baseUrl.isNotEmpty) {
      environment['CODEBUDDY_BASE_URL'] = baseUrl;
    }
    // Custom endpoints need a models.json row (OpenAI-compatible only); the
    // key is referenced by env name so it is never persisted to disk.
    if (baseUrl.isNotEmpty && model.isNotEmpty) {
      await delegate.writeJsonIfChanged(
        delegate.joinWork(configDir, 'models.json'),
        _modelsPayload(provider: provider, model: model),
      );
    }

    return SessionHomeContribution(environment: environment);
  }

  Future<AppProviderConfig?> _resolveLaunchProvider(
    SessionHomeContext ctx,
  ) async {
    final home = storage;
    if (home == null) return null;
    final resolver = CodebuddyProviderSettingsResolver(
      basePath: ctx.catalog.basePath,
      fs: ctx.catalog.fs,
      storage: home,
    );
    final team = ctx.team;
    if (team != null) {
      return resolver.resolveForLaunch(team: team, member: ctx.member);
    }
    final member = ctx.member;
    final fromMember = member?.provider.trim() ?? '';
    if (fromMember.isNotEmpty) {
      final provider = await resolver.findById(fromMember);
      if (provider != null) return provider;
    }
    final official = ctx.resolvedProviderId?.trim().isNotEmpty == true
        ? ctx.resolvedProviderId
        : defaultOfficialProviderId;
    final byId = await resolver.findById(official);
    if (byId != null) return byId;
    return resolver.resolveSole();
  }

  String _resolveModel(SessionHomeContext ctx, AppProviderConfig provider) {
    final fromMember = ctx.member?.model.trim() ?? '';
    if (fromMember.isNotEmpty) return fromMember;
    // No model chosen anywhere → leave settings.model untouched so the CLI's
    // own account default applies.
    return provider.defaultModel.trim();
  }

  /// Only an explicitly configured effort is written: the CLI/account default
  /// must win when the user never chose one (picking `xhigh` silently would
  /// make every turn dramatically more expensive).
  String _resolveEffort(AppProviderConfig provider, String model) {
    if (!isApplicable(model: model)) return '';
    return provider.config['reasoningEffort']?.toString().trim() ?? '';
  }

  Map<String, Object?> _modelsPayload({
    required AppProviderConfig provider,
    required String model,
  }) {
    final baseUrl = provider.baseUrl.trim();
    final url = baseUrl.endsWith('/chat/completions')
        ? baseUrl
        : '${baseUrl.replaceAll(RegExp(r'/+$'), '')}/chat/completions';
    return {
      'models': [
        <String, Object?>{
          'id': model,
          'name': model,
          'vendor': provider.name.trim().isEmpty ? 'custom' : provider.name,
          'apiKey': r'${CODEBUDDY_API_KEY}',
          'url': url,
          'supportsToolCall': true,
          'supportsImages': true,
        },
      ],
      'availableModels': [model],
    };
  }
}

final _emptyCatalogUpdates = _EmptyListenable();

final class _EmptyListenable implements Listenable {
  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}
