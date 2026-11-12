import '../../repositories/cli_presets_repository.dart';
import '../../repositories/extension_repository.dart';
import '../../repositories/mcp_repository.dart';
import '../../repositories/plugin_repository.dart';
import '../../repositories/skill_repository.dart';
import '../../repositories/workspace_project_config_repository.dart';
import '../../services/extension/builtin_manifests.dart';
import '../../services/skill/skill_acquisition_engine.dart';
import '../../services/skill/skill_fetch_service.dart';
import '../../services/skill/skill_install_service.dart';
import '../../services/skill/skill_manifest_service.dart';
import '../../services/skill/skill_repo_disk_cache_service.dart';
import '../../services/skill/skill_repo_git_service.dart';
import '../../services/storage/home_storage.dart';
import '../../services/storage/runtime_context.dart';

/// Skill catalog repositories plus the acquisition engine the shell boots
/// against one home plane.
typedef SkillCatalogWiring = ({
  SkillRepository skillRepository,
  SkillInstallService skillInstallService,
  SkillAcquisitionEngine skillAcquisitionEngine,
});

/// Extension catalog repositories bound to one home plane.
typedef ExtensionCatalogWiring = ({
  ExtensionRepository extensionRepository,
  WorkspaceProjectConfigRepository workspaceProjectConfigRepository,
});

/// CLI presets repository bound to one home plane.
typedef CliPresetsWiring = ({CliPresetsRepository cliPresetsRepository});

/// Plugin and MCP repositories bound to one home plane.
typedef PluginMcpWiring = ({
  PluginRepository pluginRepository,
  McpRepository mcpRepository,
});

/// Builds the skill catalog services for [storage].
SkillCatalogWiring wireSkillCatalog({required HomeStorage storage}) {
  final skillManifest = SkillManifestService(storage: storage);
  final skillGit = SkillRepoGitService();
  final skillFetch = SkillFetchService(git: skillGit);
  final skillRepoCache = SkillRepoDiskCacheService(
    storage: storage,
    fetch: skillFetch,
  );
  final skillInstallService = SkillInstallService(
    storage: storage,
    manifest: skillManifest,
    fetch: skillFetch,
    repoCache: skillRepoCache,
  );
  final skillRepo = SkillRepository(
    storage: storage,
    manifest: skillManifest,
    fetch: skillFetch,
    repoCache: skillRepoCache,
    install: skillInstallService,
  );
  final skillAcquisitionEngine = SkillAcquisitionEngine(
    storage: storage,
    installGitDir: (d, {bool overwrite = false, String? idOverride}) =>
        skillInstallService.installFromDiscovery(
          d,
          overwrite: overwrite,
          idOverride: idOverride,
        ),
    registerDirectory: ({required String id, required String directory}) =>
        skillInstallService.registerInstalledDirectory(
          id: id,
          directory: directory,
        ),
    isLocalAcquireSupported: () =>
        storage.context.mode == StorageBackendMode.native,
    repoCache: skillRepoCache,
  );
  return (
    skillRepository: skillRepo,
    skillInstallService: skillInstallService,
    skillAcquisitionEngine: skillAcquisitionEngine,
  );
}

/// Builds the extension catalog repositories for [storage].
ExtensionCatalogWiring wireExtensionCatalog({required HomeStorage storage}) {
  final extensionRepository = ExtensionRepository(
    fs: storage.fs,
    stateFilePath: storage.paths.extensionsStateJson,
    manifests: builtInExtensionManifests(),
  );
  final workspaceProjectConfigRepository = WorkspaceProjectConfigRepository(
    storage: storage,
    fs: storage.fs,
  );
  return (
    extensionRepository: extensionRepository,
    workspaceProjectConfigRepository: workspaceProjectConfigRepository,
  );
}

/// Builds the CLI presets repository for [storage].
CliPresetsWiring wireCliPresets({required HomeStorage storage}) {
  final cliPresetsRepository = CliPresetsRepository(
    fs: storage.fs,
    presetsPath: storage.paths.cliPresetsJson,
  );
  return (cliPresetsRepository: cliPresetsRepository);
}

/// Builds the plugin and MCP repositories for [storage].
PluginMcpWiring wirePluginMcp({required HomeStorage storage}) {
  final pluginRepository = PluginRepository(storage: storage);
  final mcpRepository = McpRepository(storage: storage);
  return (pluginRepository: pluginRepository, mcpRepository: mcpRepository);
}
