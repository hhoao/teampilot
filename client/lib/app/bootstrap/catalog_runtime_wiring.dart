import '../../cubits/launch_profile_cubit.dart';
import '../../repositories/mcp_repository.dart';
import '../../repositories/plugin_repository.dart';
import '../../repositories/session_repository.dart';
import '../../repositories/skill_repository.dart';
import '../../repositories/workspace_project_config_repository.dart';
import '../../services/catalog/catalog_production.dart';
import '../../services/catalog/catalog_runtime.dart';
import '../../services/plugin/plugin_repo_disk_cache_service.dart';
import '../../services/skill/registry/skill_registry_config_service.dart';
import '../../services/skill/skill_acquisition_engine.dart';
import '../../services/skill/skill_install_service.dart';
import '../../services/storage/home_storage.dart';
import '../../services/storage/runtime_context_registry.dart';

/// Assembles the shell's catalog MCP graph for the home plane.
///
/// The skill/plugin/MCP catalog modules, the marketplace discovery search and
/// install adapters, and the team-wide delete callbacks are all bound here so
/// `buildAppShell` keeps only the gateway attach and bus subscription.
///
/// [sessions] and [launchProfiles] are getters because the shell owns the
/// session repository and team cubit as `late final` dependencies.
CatalogRuntime wireCatalogRuntime({
  required HomeStorage storage,
  required SessionRepository Function() sessions,
  required RuntimeContextRegistry runtimeContexts,
  required SkillRepository skillRepository,
  required SkillInstallService skillInstall,
  required SkillAcquisitionEngine skillEngine,
  required PluginRepository pluginRepository,
  required McpRepository mcpRepository,
  required WorkspaceProjectConfigRepository workspaceConfig,
  required SkillRegistryConfigService skillRegistryConfig,
  required LaunchProfileCubit Function() launchProfiles,
}) {
  // Shell-local names so the assembly below stays identical to the call it
  // was moved out of.
  final homeStorage = storage;
  final sessionRepo = sessions();
  final skillRepo = skillRepository;
  final skillInstallService = skillInstall;
  final skillAcquisitionEngine = skillEngine;
  final workspaceProjectConfigRepository = workspaceConfig;
  final skillRegistryConfigService = skillRegistryConfig;
  final teamCubit = launchProfiles();

  return CatalogRuntime.assemble(
    storage: homeStorage,
    sessions: sessionRepo,
    runtimeContexts: runtimeContexts,
    skillRepository: skillRepo,
    skillInstall: skillInstallService,
    skillEngine: skillAcquisitionEngine,
    pluginRepository: pluginRepository,
    pluginInstall: pluginRepository.install,
    mcpRepository: mcpRepository,
    workspaceConfig: workspaceProjectConfigRepository,
    searchSkills: (query) => CatalogProduction.searchSkills(
      query,
      registryConfig: skillRegistryConfigService,
      repository: skillRepo,
    ),
    searchPlugins: (query) => CatalogProduction.searchPlugins(
      query,
      repos: pluginRepository.repos,
      diskCache: PluginRepoDiskCacheService(
        filesystem: homeStorage.fs,
        teampilotRoot: homeStorage.paths.basePath,
      ),
    ),
    searchMcp: (query) =>
        CatalogProduction.searchMcp(query, storage: homeStorage),
    draftFromListing: (listingId) =>
        CatalogProduction.draftFromListing(listingId, storage: homeStorage),
    installPluginFromDiscovery: (args) =>
        CatalogProduction.installPluginFromDiscovery(
          args,
          storage: homeStorage,
          repository: pluginRepository,
        ),
    removeSkillFromAllTeams: teamCubit.removeSkillFromAllTeams,
    removePluginFromAllTeams: teamCubit.removePluginFromAllTeams,
    removeMcpFromAllTeams: teamCubit.removeMcpFromAllTeams,
  );
}
