import 'package:flutter/widgets.dart';

import '../../../../models/app_provider_config.dart';
import '../../../../models/cli_preset.dart';
import '../../../../models/credential_action_result.dart';
import '../../../../models/credential_probe.dart';
import '../../../../models/discoverable_member.dart';
import '../../../../models/hook_entry.dart';
import '../../../../models/team_config.dart';
import '../../../agent_status/member_agent_status_endpoint.dart';
import '../../../io/filesystem.dart';
import '../../../provider/credential_binding.dart';
import '../../../remote/remote_credential_materializer.dart';
import '../../../team_bus/member_bus_idle_endpoint.dart';
import '../cli_capability.dart';
import '../config_profile/config_profile_context.dart';

/// Providers discovered from the user's global CLI install.
class ProviderCatalogSnapshot {
  const ProviderCatalogSnapshot({
    this.providers = const [],
    this.sources = const [],
    this.mirrorToFlashskyai = false,
  });

  final List<AppProviderConfig> providers;
  final List<String> sources;

  /// When true, [ProviderImportService] mirrors new ids into the flashskyai catalog.
  final bool mirrorToFlashskyai;
}

/// Inputs for scanning live CLI config on the user's machine.
class ProviderCatalogLoadContext {
  const ProviderCatalogLoadContext({
    required this.fs,
    required this.homeDirectory,
    this.cwd = '',
    this.usePosixPaths = true,
    this.flashskyaiExecutablePath,
    this.platformEnv = const {},
    this.now,
  });

  final Filesystem fs;
  final String homeDirectory;
  final String cwd;
  final bool usePosixPaths;
  final String? flashskyaiExecutablePath;

  /// Platform env overrides (e.g. `APPDATA` for Windows live-import tests).
  final Map<String, String> platformEnv;

  /// Fixed timestamp for tests; defaults to UTC now in production.
  final int? now;

  int resolvedNow() => now ?? DateTime.now().toUtc().millisecondsSinceEpoch;
}

/// Credential actions exposed in provider add/edit/detail UI.
enum ProviderCredentialActionKind {
  login,
  importGlobal,
  importFile,
  importDirectory,
  revoke,
}

/// Declares which actions a CLI supports for a given provider row.
class ProviderCredentialActionSpec {
  const ProviderCredentialActionSpec({
    required this.kind,
    this.primary = false,
    this.showWhenReady = true,
  });

  final ProviderCredentialActionKind kind;

  /// Renders as [FilledButton.tonal] when true.
  final bool primary;

  /// When false, hide this action after credentials are ready (e.g. login).
  /// When true, keep visible when ready (e.g. import, revoke / sign out).
  final bool showWhenReady;
}

/// Optional inputs for file/directory credential imports.
class ProviderCredentialActionInput {
  const ProviderCredentialActionInput({
    this.provider,
    this.pickedPath,
    this.replace = false,
    this.homeDirectory,
  });

  final AppProviderConfig? provider;
  final String? pickedPath;
  final bool replace;
  final String? homeDirectory;
}

/// Values collected from the provider form shell before [buildConfig].
class ProviderFormInput {
  const ProviderFormInput({
    required this.baseUrl,
    required this.defaultModel,
    required this.apiKeyField,
    required this.config,
    this.extra = const {},
  });

  final String baseUrl;
  final String defaultModel;
  final String apiKeyField;
  final Map<String, Object?> config;
  final Map<String, Object?> extra;
}

/// Props for CLI-specific form sections rendered below common fields.
class ProviderFormSectionProps {
  const ProviderFormSectionProps({
    required this.config,
    required this.apiKeyField,
    required this.baseUrl,
    required this.defaultModel,
    required this.extra,
    required this.onExtraChanged,
    required this.onApiKeyFieldChanged,
  });

  final Map<String, Object?> config;
  final String apiKeyField;
  final String baseUrl;
  final String defaultModel;
  final Map<String, Object?> extra;
  final ValueChanged<Map<String, Object?>> onExtraChanged;
  final ValueChanged<String> onApiKeyFieldChanged;
}

/// How member / workspace UI should collect a model id for a provider.
enum ProviderModelPickerMode {
  /// Provider bundles models (e.g. Claude official); no member model field.
  hidden,

  /// Pick from catalog only ([ProviderModelPickerMode.catalogDropdown]).
  catalogDropdown,

  /// Catalog dropdown plus free-form custom model id entry.
  catalogWithCustomEntry,
}

/// Role a model plays within a tier-aware CLI's launch config.
enum ProviderModelTier {
  /// Serves the main tiers (Claude sonnet/opus + the primary model id).
  standard('standard'),

  /// Serves the cheap/fast background tier (Claude haiku).
  background('background');

  const ProviderModelTier(this.value);

  final String value;

  static ProviderModelTier fromJson(Object? raw) {
    final s = raw?.toString().trim().toLowerCase() ?? '';
    for (final tier in ProviderModelTier.values) {
      if (tier.value == s) return tier;
    }
    return ProviderModelTier.standard;
  }
}

/// The model id flagged as the [ProviderModelTier.background] tier in the
/// provider's `config['models']`, or '' when none is designated.
String backgroundModelFromProvider(AppProviderConfig? provider) {
  if (provider == null) return '';
  final rawModels = provider.config['models'];
  if (rawModels is! Map) return '';
  for (final entry in rawModels.entries) {
    final value = entry.value;
    if (value is! Map) continue;
    final role = ProviderModelTier.fromJson(value['role']);
    if (role != ProviderModelTier.background) continue;
    final model = (value['model'] as String? ?? '').trim();
    return model.isNotEmpty ? model : entry.key.toString().trim();
  }
  return '';
}

/// Merges a CLI built-in catalog with models declared on [AppProviderConfig].
List<String> mergeProviderModelCandidates({
  required Iterable<String> builtInCatalog,
  required AppProviderConfig? provider,
  required String currentModel,
}) {
  final names = <String>{...builtInCatalog};
  if (provider != null) {
    names.addAll(modelsDeclaredOnProvider(provider));
  }
  final trimmed = currentModel.trim();
  if (trimmed.isNotEmpty) {
    names.add(trimmed);
  }
  return names.toList()..sort();
}

/// Reads `defaultModel` and `config.models` from a saved provider row.
List<String> modelsDeclaredOnProvider(AppProviderConfig provider) {
  final names = <String>{};
  final defaultModel = provider.defaultModel.trim();
  if (defaultModel.isNotEmpty) {
    names.add(defaultModel);
  }
  final rawModels = provider.config['models'];
  if (rawModels is Map) {
    for (final entry in rawModels.entries) {
      final id = entry.key.toString().trim();
      if (entry.value is Map) {
        final modelJson = Map<String, Object?>.from(entry.value as Map);
        final name = (modelJson['name'] as String? ?? '').trim();
        final model = (modelJson['model'] as String? ?? '').trim();
        if (name.isNotEmpty) names.add(name);
        if (model.isNotEmpty) names.add(model);
      } else if (id.isNotEmpty) {
        names.add(id);
      }
    }
  }
  return names.toList();
}

/// Number of models declared on [provider] for list/detail badges.
///
/// UI gates visibility via [ProviderCapability.showModelCount] — this
/// only counts what the provider row actually declares, with no CLI identity.
int providerModelCount(AppProviderConfig provider) {
  final rawModels = provider.config['models'];
  if (rawModels is Map) return rawModels.length;
  return provider.defaultModel.trim().isEmpty ? 0 : 1;
}

String resolveDefaultProviderModel(
  ProviderCapability capability, {
  required AppProviderConfig? provider,
  required String providerId,
}) {
  if (provider != null &&
      capability.pickerMode(provider) == ProviderModelPickerMode.hidden) {
    return '';
  }
  final fromProvider = provider?.defaultModel.trim() ?? '';
  if (fromProvider.isNotEmpty) return fromProvider;
  final candidates = capability.modelCandidates(
    provider: provider,
    providerId: providerId,
    currentModel: '',
  );
  return candidates.isNotEmpty ? candidates.first : '';
}

/// One composable source of built-in candidate model ids for a provider.
///
/// The provider record itself (`defaultModel` + `config['models']`) is always
/// merged on top of these by [CatalogModelCapability], so a source only
/// contributes the CLI's *built-in* knowledge (a fixed catalog, a brand list,
/// or a live `cursor-agent models` fetch). Adding a CLI = declaring its
/// [CatalogModelCapability.catalogSources].
abstract interface class ModelCatalogSource {
  List<String> modelsFor({
    required AppProviderConfig? provider,
    required String providerId,
  });
}

/// [ProviderCapability] whose model candidates are the union of its
/// [catalogSources] plus the provider record and the current value.
abstract base class CatalogModelCapability implements ProviderCapability {
  const CatalogModelCapability();

  /// Built-in catalogs merged before the provider record. Order is irrelevant
  /// (results are deduped and sorted).
  List<ModelCatalogSource> get catalogSources;

  @override
  List<String> modelCandidates({
    required AppProviderConfig? provider,
    required String providerId,
    required String currentModel,
  }) {
    final builtIn = <String>[];
    for (final source in catalogSources) {
      builtIn.addAll(
        source.modelsFor(provider: provider, providerId: providerId),
      );
    }
    return mergeProviderModelCandidates(
      builtInCatalog: builtIn,
      provider: provider,
      currentModel: currentModel,
    );
  }

  @override
  String defaultModel({
    required AppProviderConfig? provider,
    required String providerId,
  }) => resolveDefaultProviderModel(
    this,
    provider: provider,
    providerId: providerId,
  );
}

/// Where effort is configured in TeamPilot UI.
enum EffortPickerPlacement { hidden, team, member, provider }

/// Inputs for catalog filtering and launch resolution.
class EffortResolveContext {
  const EffortResolveContext({
    this.team,
    this.member,
    this.provider,
    this.model = '',
  });

  final TeamProfile? team;
  final TeamMemberConfig? member;
  final AppProviderConfig? provider;
  final String model;
}

String resolveContextModel(EffortResolveContext context) {
  final explicit = context.model.trim();
  if (explicit.isNotEmpty) return explicit;
  final memberModel = context.member?.model.trim() ?? '';
  if (memberModel.isNotEmpty) return memberModel;
  return context.provider?.defaultModel.trim() ?? '';
}

/// Launch precedence: member → team → provider config → capability default.
String resolveLaunchEffort({
  required ProviderCapability capability,
  required CliTool cli,
  required EffortResolveContext context,
}) {
  final model = resolveContextModel(context);
  if (!capability.isApplicable(model: model)) return '';

  final memberEffort = context.member?.effort.trim() ?? '';
  if (memberEffort.isNotEmpty &&
      capability.memberPickerPlacement(provider: context.provider) !=
          EffortPickerPlacement.hidden) {
    return memberEffort;
  }

  final teamEffort = context.team?.effortForCli(cli).trim() ?? '';
  if (teamEffort.isNotEmpty &&
      capability.teamPickerPlacement() != EffortPickerPlacement.hidden) {
    return teamEffort;
  }

  final provider = context.provider;
  final providerEffort = _providerConfiguredEffort(provider);
  if (provider != null &&
      providerEffort.isNotEmpty &&
      capability.providerPickerPlacement(provider) !=
          EffortPickerPlacement.hidden) {
    return providerEffort;
  }

  return capability.defaultEffort(model: model, provider: context.provider);
}

String _providerConfiguredEffort(AppProviderConfig? provider) {
  if (provider == null) return '';
  final fromConfig = provider.config['model_reasoning_effort']
      ?.toString()
      .trim();
  if (fromConfig != null && fromConfig.isNotEmpty) return fromConfig;
  final reasoningEffort = provider.config['reasoningEffort']?.toString().trim();
  if (reasoningEffort != null && reasoningEffort.isNotEmpty) {
    return reasoningEffort;
  }
  final effort = provider.config['effort']?.toString().trim();
  if (effort != null && effort.isNotEmpty) return effort;
  return '';
}

/// Session-home materialization inputs, mirroring [ConfigProfileLaunchContext].
class SessionHomeContext {
  const SessionHomeContext({
    required this.workspaceId,
    required this.teamId,
    required this.sessionId,
    required this.scope,
    required this.tool,
    required this.paths,
    required this.catalog,
    required this.members,
    this.team,
    this.member,
    this.workingDirectory = '',
    this.additionalDirectories = const [],
    this.leadSessionId,
    this.busIdle,
    this.agentStatus,
    this.preset,
    this.memberId,
    this.sessionExpertKey,
    this.resolvedExpert,
    this.hooks = const [],
    this.crossMachine = false,
    this.resolvedProviderId,
    this.credentialBasePath,
    this.isSimple = false,
  });

  final String workspaceId;
  final String teamId;
  final String sessionId;
  final LaunchProfileScope scope;
  final CliTool tool;
  final TeamProfile? team;
  final TeamMemberConfig? member;
  final List<TeamMemberConfig> members;
  final String? workingDirectory;
  final List<String> additionalDirectories;

  /// Work-plane delegate: session runtime trees, settings writes, hooks.
  final ConfigProfileDelegate paths;

  /// Control-plane paths: provider catalog and home credential reads.
  final ConfigProfilePaths catalog;
  final String? leadSessionId;
  final MemberBusIdleEndpoint? busIdle;

  /// Permission / status HTTP hooks (`POST /agent-status`). Stamped at
  /// lifecycle (Task 7); null until then — writers install only when set.
  final MemberAgentStatusEndpoint? agentStatus;
  final CliPreset? preset;
  final String? memberId;
  final String? sessionExpertKey;
  final DiscoverableMember? resolvedExpert;

  /// 该 seat 生效的用户 hook 条目(staging 按 runtimeBundle.hookIds 解析)。
  final List<HookEntry> hooks;

  /// True when the work plane is not the control plane (SSH/WSL session).
  final bool crossMachine;

  /// Provider id resolved by the orchestrator when it precedes this call.
  final String? resolvedProviderId;

  /// Control-plane base path for credential artifacts when [crossMachine].
  final String? credentialBasePath;

  /// True when launching Simple (unteamed). Team launches always pass a
  /// non-empty [teamId] even when the [TeamProfile] object is omitted.
  final bool isSimple;
}

/// Environment + warnings produced by [ProviderCapability.materializeSessionHome].
class SessionHomeContribution {
  const SessionHomeContribution({
    this.environment = const {},
    this.warnings = const [],
  });

  final Map<String, String> environment;
  final List<String> warnings;
}

/// Converts a launch context into session-home inputs for [materializeSessionHome].
SessionHomeContext sessionHomeContextFromLaunch(
  ConfigProfileLaunchContext ctx,
  CliTool tool, {
  String? resolvedProviderId,
  String? credentialBasePath,
}) {
  return SessionHomeContext(
    workspaceId: ctx.workspaceId,
    teamId: ctx.teamId,
    sessionId: ctx.sessionId,
    scope: ctx.scope,
    tool: tool,
    team: ctx.team,
    member: ctx.member,
    members: ctx.members,
    workingDirectory: ctx.workingDirectory,
    additionalDirectories: ctx.additionalDirectories,
    paths: ctx.paths,
    catalog: ctx.catalog,
    leadSessionId: ctx.leadSessionId,
    busIdle: ctx.busIdle,
    agentStatus: ctx.agentStatus,
    preset: ctx.preset,
    memberId: ctx.memberId,
    sessionExpertKey: ctx.sessionExpertKey,
    resolvedExpert: ctx.resolvedExpert,
    hooks: ctx.hooks,
    crossMachine: ctx.crossMachine,
    resolvedProviderId: resolvedProviderId,
    credentialBasePath: credentialBasePath,
    isSimple: ctx.isSimple,
  );
}

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

  /// Whether this CLI supports the link-vs-isolated credential binding
  /// concept (only claude). Other CLIs return false so the binding UI and
  /// binding writes stay claude-only, matching the pre-merge capability
  /// absence.
  bool get supportsCredentialBinding => false;
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

  // ---- Session-home materialization (formerly ConfigProfileCapability) ----
  Future<SessionHomeContribution> materializeSessionHome(SessionHomeContext ctx);
}

/// Marker: this CLI's model catalog can be refreshed live
/// (`cursor-agent models`, models.dev). Consumers use `is` checks to gate
/// refresh affordances; non-refreshable CLIs return no-op members.
abstract interface class RefreshableProviderModelCapability
    implements ProviderCapability {}

final _emptyCatalogUpdates = _EmptyListenable();

final class _EmptyListenable implements Listenable {
  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}
