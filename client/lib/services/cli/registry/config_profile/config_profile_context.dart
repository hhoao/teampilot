import 'package:path/path.dart' as p;

import '../../../../models/cli_preset.dart';
import '../../../../models/hook_entry.dart';
import '../../../../models/discoverable_member.dart';
import '../../../../models/team_config.dart';
import '../../../extension/extension_provisioner.dart';
import '../../../io/filesystem.dart';
import '../../../host/host_execution_environment.dart';
import '../../../provider/provider_catalog_access.dart';
import '../../../storage/runtime_layout.dart';
import '../../../agent_status/member_agent_status_endpoint.dart';
import '../../../team_bus/member_bus_idle_endpoint.dart';
import '../../../resource/providers/hook_contribution_provider.dart';
import '../../../resource/providers/hook_library_contribution_provider.dart';
import '../../../resource/resource_provider_set.dart';
import 'config_profile_scope.dart';

export 'config_profile_scope.dart';

/// Resolve CLI/provider/model/effort for a session from its active preset.
/// Returns null if no preset is active, not found, or [activePresetId] is empty.
CliPreset? resolveActivePreset(
  String? activePresetId,
  List<CliPreset> presets,
) {
  if (activePresetId == null || activePresetId.isEmpty) return null;
  for (final p in presets) {
    if (p.id == activePresetId) return p;
  }
  return null;
}

String presetProviderId(CliPreset? preset) {
  return preset?.provider.trim() ?? '';
}

String presetModelId(CliPreset? preset) {
  return preset?.model.trim() ?? '';
}

CliTool presetCli(CliPreset? preset, {CliTool fallback = CliTool.claude}) {
  return preset?.cli ?? fallback;
}

/// Path facade for launch config-profile materialization.
abstract interface class ConfigProfilePaths {
  String get basePath;

  /// Runtime user home (`native` / `wsl` / `ssh`), used for global CLI state
  /// such as Cursor workspace trust markers under `$HOME/.cursor/projects/`.
  String get home;

  Filesystem get fs;

  p.Context get pathContext;

  RuntimeLayout get layout;

  String sessionToolDir(
    String workspaceId,
    String sessionId,
    String tool, {
    String? memberId,
  });
}

/// Shared profile I/O, extension settings hooks, and team-lead scripts.
abstract interface class ConfigProfileDelegate implements ConfigProfilePaths {
  Future<Map<String, Object?>> readMetadataFile(
    String path,
    Map<String, Object?> defaults,
  );

  Future<void> writeJsonIfChanged(String path, Map<String, Object?> value);

  Future<Map<String, Object?>> metadataWithTrustedProjects({
    required String metadataPath,
    required Map<String, Object?> defaultMetadata,
    required Map<String, Object?> defaultProjectConfig,
    required Iterable<String> directories,
  });

  Future<bool> trustedProjectsAlreadyCurrent(
    String metadataPath,
    Iterable<String> directories, {
    required Map<String, Object?> defaultMetadata,
  });

  Future<Map<String, Object?>> readSettingsFile(String path);

  Future<void> writeSettingsFile(
    String path,
    Map<String, Object?> settings, {
    String? memberToolDir,
    required String tool,
    String? teamId,
    String? workspaceId,
  });

  Future<Map<String, Object?>> applyExtensionSettings(
    Map<String, Object?> settings,
    String? memberToolDir, {
    required String tool,
    String? teamId,
    String? workspaceId,
  });

  /// Renders every enabled, ready extension's `settings-hook` effects into
  /// [HookEntry]-backed specs (scripts provisioned under [memberToolDir]).
  /// Consumed by the unified hook writer render at the member-profile
  /// assembly points (Task 18 convergence).
  Future<List<ExtensionSettingsHook>> extensionSettingsHooks(
    String? memberToolDir, {
    required String tool,
    String? teamId,
    String? workspaceId,
  });

  Future<Map<String, Object?>> maybeApplyTeamLeadHooks(
    Map<String, Object?> settings,
    TeamMemberConfig member,
    String memberToolDir, {
    required bool forceTeamLeadDelegateMode,
  });

  /// Provisioned team-lead delegate-only PreToolUse hook command (script
  /// written under [memberToolDir]), or null when [member] is not the team
  /// lead or delegate mode is off. The assembly point folds it into the
  /// unified hook writer render (Task 18 convergence).
  Future<String?> resolveTeamLeadDelegateHookCommand(
    TeamMemberConfig member,
    String memberToolDir, {
    required bool forceTeamLeadDelegateMode,
  });

  HostExecutionEnvironment hostEnvironmentForProvision();
}

class ConfigProfileLaunchContext {
  ConfigProfileLaunchContext({
    required this.workspaceId,
    required this.teamId,
    required this.sessionId,
    required this.scope,
    this.team,
    this.member,
    required this.members,
    this.workingDirectory = '',
    this.additionalDirectories = const [],
    required this.paths,
    required this.catalog,
    this.leadSessionId,
    this.busIdle,
    this.agentStatus,
    this.preset,
    this.memberId,
    this.sessionExpertKey,
    this.resolvedExpert,
    ResourceProviderSet resourceProviders = ResourceProviderSet.empty,
    // Kept only as a source-compatible boundary adapter for older callers.
    this.hooks = const [],
    this.hookLibraryProvider,
  }) : resourceProviders = _withLegacyHookProviders(
         resourceProviders,
         hooks: hooks,
         hookLibraryProvider: hookLibraryProvider,
       );

  final String workspaceId;
  final String teamId;
  final String sessionId;
  final LaunchProfileScope scope;
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

  /// All launch-injected resource sources, grouped by kind and ordered.
  final ResourceProviderSet resourceProviders;

  /// Legacy compatibility projection. New staging callers pass
  /// [resourceProviders]; this boundary is removed once downstream provider
  /// capabilities consume the grouped set directly.
  final List<HookEntry> hooks;
  final HookContributionProvider? hookLibraryProvider;

  bool get crossMachine => configProfileCrossMachine(catalog, paths);

  /// True when launching Simple (unteamed). Team launches always pass a
  /// non-empty [teamId] even when the [TeamProfile] object is omitted.
  bool get isSimple => teamId.trim().isEmpty;
}

ResourceProviderSet _withLegacyHookProviders(
  ResourceProviderSet providers, {
  required List<HookEntry> hooks,
  required HookContributionProvider? hookLibraryProvider,
}) {
  if (hooks.isEmpty && hookLibraryProvider == null) return providers;
  final existingIds = providers.hooks
      .map((provider) => provider.providerId)
      .toSet();
  return ResourceProviderSet(
    prompts: providers.prompts,
    skills: providers.skills,
    mcp: providers.mcp,
    hooks: [
      ...providers.hooks,
      if (hookLibraryProvider != null &&
          existingIds.add(hookLibraryProvider.providerId))
        hookLibraryProvider,
      if (hooks.isNotEmpty && existingIds.add('user-library'))
        UserHookContributionProvider(entries: hooks),
    ],
  );
}
