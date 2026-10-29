import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';

import '../../../../models/app_provider_config.dart';
import '../../../../models/credential_action_result.dart';
import '../../../../models/credential_probe.dart';
import '../../../../widgets/home_storage_scope.dart';
import '../../../io/filesystem.dart';
import '../../../provider/credential_binding.dart';
import '../../../provider/passthrough_provider_form_capability.dart';
import '../../../remote/remote_credential_materializer.dart';
import '../../../storage/home_storage.dart';
import '../../registry/capabilities/interactive_login_capability.dart';
import '../../registry/capabilities/provider_capability.dart';
import '../provider/antigravity_login_dialog.dart';
import '../provider/antigravity_model_catalog.dart';
import '../provider/antigravity_provider_settings_resolver.dart';
import '../provider_presets.dart';

final class _AntigravityCatalogSource implements ModelCatalogSource {
  const _AntigravityCatalogSource();

  @override
  List<String> modelsFor({
    required AppProviderConfig? provider,
    required String providerId,
  }) => AntigravityModelCatalog.modelsFor(
    provider: provider,
    providerId: providerId,
  );
}

/// How a provider row authenticates against the Antigravity ACP adapter.
///
/// The adapter reads `auth.type` from `settings.json`; only the API-key row
/// also needs `modelProvider: gemini` in the CLI settings.
enum _AntigravityAuthMode {
  /// `oauth-personal`: the account signs in through `agy` and lives in the OS
  /// keyring (shared by every official row).
  official('oauth-personal'),

  /// `gemini-api-key`: `GEMINI_API_KEY` in the process env, never on disk.
  geminiApiKey('gemini-api-key'),

  /// `agent-platform`: Application Default Credentials from the host.
  adc('agent-platform');

  const _AntigravityAuthMode(this.authType);

  final String authType;

  static _AntigravityAuthMode? fromConfig(Object? raw) {
    final value = raw?.toString().trim().toLowerCase() ?? '';
    for (final mode in values) {
      if (value == mode.authType) return mode;
    }
    return switch (value) {
      'oauth' || 'google' => official,
      'gemini' || 'api-key' || 'api_key' => geminiApiKey,
      'adc' || 'vertex' => adc,
      _ => null,
    };
  }
}

/// Config key presets/forms use to pin the auth mode explicitly.
const _authModeConfigKey = 'authMode';

/// Antigravity provider stack: static model catalog, `agy` interactive login
/// for the official Google account, and per-session settings files under the
/// isolated `HOME` that [AntigravityAcpCapability] launches the adapter with.
///
/// API keys never reach `settings.json`; they travel in the process env
/// (`GEMINI_API_KEY`) through [SessionHomeContribution.environment].
final class AntigravityProviderCapability extends CatalogModelCapability
    with PassthroughProviderFormDefaults
    implements ProviderCapability, InteractiveCliLoginCapability {
  const AntigravityProviderCapability({this.storage});

  /// Home control-plane storage injected at registry construction; required to
  /// read the provider catalog and to host the login terminal.
  final HomeStorage? storage;

  static const _modelProviderApiKey = 'gemini';

  // ---- ProviderCatalogCapability ----
  @override
  CliTool get catalogCli => CliTool.antigravity;

  @override
  String? get defaultOfficialProviderId => 'antigravity';

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
  List<AppProviderPreset> get presets => AntigravityProviderPresets.all;

  @override
  Map<String, Object?> defaultConfig() => const {};

  @override
  String defaultApiKeyField() => 'api_key';

  // ---- ProviderModelCapability (static catalog) ----
  @override
  bool get supportsModelTiers => false;

  @override
  List<ModelCatalogSource> get catalogSources => const [
    _AntigravityCatalogSource(),
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

  // ---- ProviderCredentialCapability (Google account via agy login) ----
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

  /// The OAuth token lives in the OS keyring, which TeamPilot cannot read
  /// without running the CLI, so readiness is reported as missing and the
  /// login action stays available.
  @override
  Future<CredentialProbe> probe(AppProviderConfig provider) async =>
      CredentialProbe(
        providerId: provider.id,
        status: CredentialStatus.missing,
        credentialPath: '',
      );

  /// The login dialog verifies the sign-in with `agy models` before returning,
  /// so a completed login is recorded as success here.
  @override
  Future<CredentialActionResult> execute({
    required String providerId,
    required ProviderCredentialActionKind kind,
    ProviderCredentialActionInput input = const ProviderCredentialActionInput(),
  }) async {
    if (kind != ProviderCredentialActionKind.login) {
      return CredentialActionResult.unsupported();
    }
    return CredentialActionResult.success;
  }

  @override
  bool hidesApiKeyFields(AppProviderConfig provider) =>
      _resolveAuthMode(provider) != _AntigravityAuthMode.geminiApiKey;

  // ---- InteractiveCliLoginCapability ----
  @override
  String get loginExecutableName => 'agy';

  @override
  List<String> get loginArguments => const [];

  @override
  Widget buildLoginDialog(
    BuildContext context, {
    required AppProviderConfig provider,
    required String executable,
  }) => AntigravityLoginDialog(
    provider: provider,
    executable: executable,
    storage: storage ?? homeStorageOf(context),
  );

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

  // ---- CliEffortCapability (`--effort` / ACP config option) ----
  @override
  EffortPickerPlacement teamPickerPlacement() => EffortPickerPlacement.team;

  @override
  EffortPickerPlacement memberPickerPlacement({AppProviderConfig? provider}) =>
      EffortPickerPlacement.member;

  @override
  EffortPickerPlacement providerPickerPlacement(AppProviderConfig provider) =>
      EffortPickerPlacement.provider;

  @override
  bool isApplicable({required String model}) => model.trim().isNotEmpty;

  @override
  List<String> effortCandidates({
    required String model,
    AppProviderConfig? provider,
  }) => isApplicable(model: model) ? const ['low', 'medium', 'high'] : const [];

  /// Empty unless the row pins one: model slugs already encode an effort and
  /// silently forcing `high` would change cost for every launch.
  @override
  String defaultEffort({required String model, AppProviderConfig? provider}) {
    final fromProvider = provider?.config['effort']?.toString().trim() ?? '';
    return effortCandidates(
          model: model,
          provider: provider,
        ).contains(fromProvider)
        ? fromProvider
        : '';
  }

  // ---- Session-home materialization ----
  @override
  Future<SessionHomeContribution> materializeSessionHome(
    SessionHomeContext ctx,
  ) async {
    final paths = ctx.paths;
    final fs = paths.fs;
    final pc = paths.pathContext;
    final toolDir = paths.sessionToolDir(
      ctx.workspaceId,
      ctx.sessionId,
      CliTool.antigravity.value,
      memberId: ctx.memberId,
    );
    final home = pc.join(toolDir, 'home');
    final cliDir = pc.join(home, '.gemini', 'antigravity-cli');
    final acpDir = pc.join(home, '.gemini', 'antigravity-acp');
    await fs.ensureDir(cliDir);
    await fs.ensureDir(acpDir);

    final provider = await _resolveLaunchProvider(ctx);
    final authMode = _resolveAuthMode(provider);
    final model = _resolveModel(ctx, provider);

    await _mergeJson(
      fs,
      pc.join(cliDir, 'settings.json'),
      {
        if (model.isNotEmpty) 'model': model,
        if (authMode == _AntigravityAuthMode.geminiApiKey)
          'modelProvider': _modelProviderApiKey,
      },
      remove: [
        if (authMode != _AntigravityAuthMode.geminiApiKey) 'modelProvider',
      ],
    );
    await _mergeJson(fs, pc.join(acpDir, 'settings.json'), {
      'auth': {'type': authMode.authType},
    });

    return SessionHomeContribution(environment: _authEnv(provider, authMode));
  }

  /// Explicit `config.authMode` wins; otherwise the row shape decides:
  /// official → Google account, cloud-provider rows → ADC, the rest → API key.
  _AntigravityAuthMode _resolveAuthMode(AppProviderConfig? provider) {
    if (provider == null) return _AntigravityAuthMode.official;
    final configured = _AntigravityAuthMode.fromConfig(
      provider.config[_authModeConfigKey],
    );
    if (configured != null) return configured;
    if (provider.isOfficial) return _AntigravityAuthMode.official;
    if (provider.category == AppProviderCategory.cloudProvider) {
      return _AntigravityAuthMode.adc;
    }
    final id = provider.id.toLowerCase();
    if (id.contains('adc') ||
        id.contains('agent-platform') ||
        id.contains('vertex')) {
      return _AntigravityAuthMode.adc;
    }
    return _AntigravityAuthMode.geminiApiKey;
  }

  /// Google-account rows need nothing; API keys travel in the process env and
  /// ADC turns on the adapter's `agent-platform` path.
  Map<String, String> _authEnv(
    AppProviderConfig? provider,
    _AntigravityAuthMode authMode,
  ) {
    final p = provider;
    if (p == null) return const {};
    return switch (authMode) {
      _AntigravityAuthMode.official => const {},
      _AntigravityAuthMode.geminiApiKey => {
        if (p.apiKey.trim().isNotEmpty) 'GEMINI_API_KEY': p.apiKey.trim(),
        if (p.baseUrl.trim().isNotEmpty)
          'GOOGLE_GEMINI_BASE_URL': p.baseUrl.trim(),
      },
      _AntigravityAuthMode.adc => {
        'AGY_ADC_AUTH': 'true',
        if (_configText(p, 'project').isNotEmpty)
          'GOOGLE_CLOUD_PROJECT': _configText(p, 'project'),
        if (_configText(p, 'location').isNotEmpty)
          'GOOGLE_CLOUD_LOCATION': _configText(p, 'location'),
      },
    };
  }

  String _configText(AppProviderConfig provider, String key) =>
      provider.config[key]?.toString().trim() ?? '';

  Future<AppProviderConfig?> _resolveLaunchProvider(
    SessionHomeContext ctx,
  ) async {
    final home = storage;
    if (home == null) return null;
    final resolver = AntigravityProviderSettingsResolver(
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

  String _resolveModel(SessionHomeContext ctx, AppProviderConfig? provider) {
    final fromMember = ctx.member?.model.trim() ?? '';
    if (fromMember.isNotEmpty) return fromMember;
    final fromPreset = ctx.preset?.model.trim() ?? '';
    if (fromPreset.isNotEmpty) return fromPreset;
    // No model chosen anywhere → leave settings.model untouched so the CLI's
    // own default applies.
    return provider?.defaultModel.trim() ?? '';
  }
}

/// Merges [patch] into the JSON object at [path], keeping unknown keys. Nested
/// maps merge recursively so `auth.type` does not drop sibling `auth` keys.
/// [remove] deletes top-level keys the patch no longer owns.
Future<void> _mergeJson(
  Filesystem fs,
  String path,
  Map<String, Object?> patch, {
  Iterable<String> remove = const [],
}) async {
  final existingText = await fs.readString(path);
  final existing = existingText == null || existingText.trim().isEmpty
      ? <String, Object?>{}
      : (jsonDecode(existingText) as Map).cast<String, Object?>();
  final merged = _deepMerge(existing, patch);
  for (final key in remove) {
    merged.remove(key);
  }
  await fs.ensureDir(fs.pathContext.dirname(path));
  await fs.atomicWrite(
    path,
    const JsonEncoder.withIndent('  ').convert(merged),
  );
}

Map<String, Object?> _deepMerge(
  Map<String, Object?> base,
  Map<String, Object?> patch,
) {
  final out = <String, Object?>{...base};
  patch.forEach((key, value) {
    final current = out[key];
    if (current is Map && value is Map) {
      out[key] = _deepMerge(
        current.cast<String, Object?>(),
        value.cast<String, Object?>(),
      );
    } else {
      out[key] = value;
    }
  });
  return out;
}

final _emptyCatalogUpdates = _EmptyListenable();

final class _EmptyListenable implements Listenable {
  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}
