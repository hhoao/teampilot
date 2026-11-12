import 'dart:async';

import '../../cubits/expert_hub_cubit.dart';
import '../../cubits/hook_cubit.dart';
import '../../cubits/launch_profile_cubit.dart';
import '../../cubits/mcp_cubit.dart';
import '../../cubits/plugin_cubit.dart';
import '../../cubits/skill_cubit.dart';
import '../../cubits/team_hub_cubit.dart';
import '../../cubits/workspace_project_config_cubit.dart';
import '../../models/install_job/install_cancel_policy.dart';
import '../../models/install_job/install_job_spec.dart';
import '../../repositories/mcp_repository.dart';
import '../../repositories/plugin_repository.dart';
import '../../repositories/skill_repository.dart';
import '../../repositories/workspace_project_config_repository.dart';
import '../../services/catalog/catalog_workspace_binder.dart';
import '../../services/chat/launch/staging/session_runtime_plan_builder.dart';
import '../../services/expert_hub/composite_expert_hub_source.dart';
import '../../services/expert_hub/expert_capability_resolver.dart';
import '../../services/expert_hub/expert_clone_service.dart';
import '../../services/expert_hub/expert_hub_catalog.dart';
import '../../services/expert_hub/expert_hub_favorites_store.dart';
import '../../services/expert_hub/git_registry_expert_hub_source.dart';
import '../../services/expert_hub/local_expert_store.dart';
import '../../services/expert_hub/member_roster_service.dart';
import '../../services/hook/hook_repository.dart';
import '../../services/install/install_job_keys.dart';
import '../../services/install/install_job_registry.dart';
import '../../services/install/runners/hub_clone_install_job_runner.dart';
import '../../services/mcp/mcp_dart_probe_handshake.dart';
import '../../services/mcp/mcp_server_probe_service.dart';
import '../../services/storage/device_local_control_plane.dart';
import '../../services/storage/home_storage.dart';
import '../../services/team_config/team_clone_service.dart';
import '../../services/team_hub/composite_team_hub_source.dart';
import '../../services/team_hub/git_registry_team_hub_source.dart';
import '../../services/team_hub/team_hub_favorites_store.dart';
import '../../utils/logging/logger.dart';

/// Hub state bound to one home plane: the catalog workspace binder, the team
/// and expert hub catalogs with their favorites stores, the expert capability
/// resolver and roster service, and the runtime plan builder built on them.
///
/// The MCP/hook/team-hub/expert-hub cubits are created here too because their
/// construction is interleaved with the hub stores: the shell assigns its
/// fields from this record right after the call.
typedef HubWiring = ({
  McpCubit mcpCubit,
  HookCubit hookCubit,
  TeamHubCubit teamHubCubit,
  ExpertHubCubit expertHubCubit,
  CatalogWorkspaceBinder catalogWorkspaceBinder,
  TeamHubFavoritesStore teamHubFavorites,
  ExpertHubCatalog expertHubCatalog,
  ExpertCapabilityResolver expertCapabilityResolver,
  MemberRosterService memberRosterService,
  SessionRuntimePlanBuilder sessionRuntimePlanBuilder,
  LocalExpertStore localExpertStore,
  Future<void> Function(String mcpId) unbindMcpEverywhere,
});

/// Builds the team and expert hub wiring for the home plane behind [storage].
///
/// [nativeAppDataPath] roots the device-local catalog caches. Unreachable SSH
/// homes ([deferHomePlaneLoads]) skip the local expert store loads; the
/// post-connect chain reloads them.
Future<HubWiring> wireHubs({
  required String nativeAppDataPath,
  required HomeStorage storage,
  required LaunchProfileCubit teamCubit,
  required WorkspaceProjectConfigRepository workspaceConfig,
  required McpRepository mcpRepository,
  required HookRepository hookRepository,
  required SkillCubit skillCubit,
  required PluginCubit pluginCubit,
  required SkillRepository skillRepository,
  required PluginRepository pluginRepository,
  required InstallJobRegistry installJobRegistry,
  required bool deferHomePlaneLoads,
}) async {
  final catalogWorkspaceBinder = CatalogWorkspaceBinder(
    repo: workspaceConfig,
  );
  Future<void> unbindMcpEverywhere(String mcpId) async {
    await teamCubit.removeMcpFromAllTeams(mcpId);
    final changed = await catalogWorkspaceBinder.unbindMcpFromAllWorkspaces(
      mcpId,
    );
    for (final workspaceId in changed) {
      await WorkspaceProjectConfigCubit.reloadLive(workspaceId);
    }
  }

  final mcpCubit = McpCubit(
    mcpRepository,
    storage: storage,
    onMcpUnbound: unbindMcpEverywhere,
    probeService: McpServerProbeService(
      handshake: McpDartProbeHandshake(storage: storage),
    ),
  );
  final hookCubit = HookCubit(repository: hookRepository)..load();

  // Catalog caches are device-local: on Android the home root is remote
  // (SFTP), so a cache under it costs a network round trip per read.
  final catalogCacheRoot = deviceLocalCatalogCacheRoot(nativeAppDataPath);
  final catalogCacheFs = deviceLocalCatalogCacheFilesystem(nativeAppDataPath);
  final teamHubSource = CompositeTeamHubSource.withDefaults(
    GitRegistryTeamHubSource(
      storage: storage,
      fs: catalogCacheFs,
      cacheDirOverride: '$catalogCacheRoot/team-hub',
    ),
  );
  final teamHubFavorites = TeamHubFavoritesStore(storage: storage);
  final localExpertStore = LocalExpertStore(
    fs: storage.fs,
    dirOverride: storage.paths.memberHubLocalTemplatesDir,
  );
  // Unreachable SSH home: defer these home-plane reads to the post-connect
  // chain (the catalog warm below is already background and tolerates an
  // empty local store meanwhile).
  if (!deferHomePlaneLoads) {
    await localExpertStore.migrateLegacyLayout();
    await localExpertStore.ensureIndexLoaded();
  }
  final compositeExpertHubSource = CompositeExpertHubSource.withDefaults(
    registry: GitRegistryExpertHubSource(
      storage: storage,
      fs: catalogCacheFs,
      cacheDirOverride: '$catalogCacheRoot/member-hub',
    ),
    teamIndex: teamHubSource.fetchTeams,
    localStore: localExpertStore,
  );
  final expertHubCatalog = ExpertHubCatalog(source: compositeExpertHubSource);
  // The home-index load materializes every team roster, which blocks on this
  // catalog's first snapshot (registry fetch on a cold cache). Warm it now so
  // that read overlaps the rest of shell wiring instead of the splash.
  unawaited(() async {
    try {
      await expertHubCatalog.snapshot();
    } on Object catch (error, stackTrace) {
      appLogger.w(
        '[boot] expert catalog warm failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }());
  final expertCloneService = ExpertCloneService(
    source: compositeExpertHubSource,
    store: localExpertStore,
    catalog: expertHubCatalog,
  );
  final teamCloneService = TeamCloneService(
    installSkill: skillCubit.installTeamDependency,
    installPlugin: pluginCubit.installTeamDependency,
    installMcp: mcpCubit.installTeamDependency,
    expertCloner: expertCloneService.clone,
    createTeam:
        ({
          required name,
          required cli,
          required teamMode,
          required roster,
          required skillIds,
          required pluginIds,
          required mcpServerIds,
          required description,
          required extraArgs,
          hubSourceKey,
        }) => teamCubit.addClonedTeam(
          name: name,
          cli: cli,
          teamMode: teamMode,
          roster: roster,
          skillIds: skillIds,
          pluginIds: pluginIds,
          mcpServerIds: mcpServerIds,
          description: description,
          extraArgs: extraArgs,
          hubSourceKey: hubSourceKey,
        ),
  );
  final teamHubCubit = TeamHubCubit(
    source: teamHubSource,
    loadFavorites: teamHubFavorites.load,
    saveFavoriteToggle: teamHubFavorites.toggle,
    cloneTeam: (team, {teamMode, cli}) => installJobRegistry.enqueue(
      InstallJobSpec(
        key: InstallJobKeys.hubTeam(team.key),
        title: 'Clone ${team.name}',
        cancelPolicy: InstallCancelPolicy.cooperative,
        historyMessageFor: (result) => result.hasFailures
            ? 'Cloned ${team.name} with ${result.failedDeps.length} dependency failures'
            : 'Cloned ${team.name}',
        run: (ctx) => teamCloneService.clone(
          team,
          teamMode: teamMode,
          cli: cli,
          onProgress: (progress) => reportHubCloneProgress(ctx, progress),
        ),
      ),
    ),
    loadInstalledDepIds: () async {
      final skills = await skillRepository.loadInstalled();
      final plugins = await pluginRepository.loadAll();
      final mcps = await mcpRepository.loadAll();
      return <String>{
        ...skills.map((s) => s.id),
        ...plugins.map((p) => p.id),
        ...mcps.map((m) => m.id),
      };
    },
  );

  final expertHubFavorites = ExpertHubFavoritesStore(storage: storage);
  teamCubit.attachCatalog(expertHubCatalog);
  final expertCapabilityResolver = ExpertCapabilityResolver(
    installSkill: skillCubit.installTeamDependency,
    installPlugin: pluginCubit.installTeamDependency,
    installMcp: mcpCubit.installTeamDependency,
    localStore: localExpertStore,
    source: compositeExpertHubSource,
  );
  final memberRosterService = MemberRosterService(
    resolver: expertCapabilityResolver,
  );
  final expertHubCubit = ExpertHubCubit(
    source: compositeExpertHubSource,
    loadFavorites: expertHubFavorites.load,
    saveFavoriteToggle: expertHubFavorites.toggle,
    memberRosterService: memberRosterService,
    launchProfiles: () => teamCubit,
    installJobRegistry: installJobRegistry,
    loadInstalledDepIds: () async {
      final skills = await skillRepository.loadInstalled();
      return skills.map((s) => s.id).toSet();
    },
  );
  expertCapabilityResolver.attachHubCubit(expertHubCubit);
  final sessionRuntimePlanBuilder = SessionRuntimePlanBuilder(
    expertResolver: expertCapabilityResolver,
    workspaceProjectConfig: workspaceConfig,
  );

  return (
    mcpCubit: mcpCubit,
    hookCubit: hookCubit,
    teamHubCubit: teamHubCubit,
    expertHubCubit: expertHubCubit,
    catalogWorkspaceBinder: catalogWorkspaceBinder,
    teamHubFavorites: teamHubFavorites,
    expertHubCatalog: expertHubCatalog,
    expertCapabilityResolver: expertCapabilityResolver,
    memberRosterService: memberRosterService,
    sessionRuntimePlanBuilder: sessionRuntimePlanBuilder,
    localExpertStore: localExpertStore,
    unbindMcpEverywhere: unbindMcpEverywhere,
  );
}
