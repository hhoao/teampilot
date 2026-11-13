import '../../cubits/progress_activity_cubit.dart';
import '../../cubits/repo_clone_cubit.dart';
import '../../cubits/session_preferences_cubit.dart';
import '../../models/runtime_target.dart';
import '../../models/session_preferences.dart';
import '../../models/skill_registry_source.dart';
import '../../models/ssh_profile.dart';
import '../../repositories/app_settings_repository.dart';
import '../../repositories/ssh_profile_repository.dart';
import '../../services/app/app_update_service.dart';
import '../../services/cli/cli_installer_service.dart';
import '../../services/cli/registry/capabilities/acp_settings_capability.dart';
import '../../services/cli/registry/cli_tool_registry.dart';
import '../../services/file_tree_import/workspace_import_service.dart';
import '../../services/host/process_run_handle.dart';
import '../../services/install/install_job_registry.dart';
import '../../services/install/install_job_runner_registry.dart';
import '../../services/install/runners/app_update_install_job_runner.dart';
import '../../services/install/runners/cli_install_job_runner.dart';
import '../../services/install/runners/file_tree_import_install_job_runner.dart';
import '../../services/install/runners/hub_clone_install_job_runner.dart';
import '../../services/install/runners/pack_acquire_install_job_runner.dart';
import '../../services/install/runners/toolchain_install_job_runner.dart';
import '../../services/run/process_run_executor.dart';
import '../../services/run/run_target_resolver.dart';
import '../../services/skill/registry/skill_registry_config_service.dart';
import '../../services/ssh/ssh_client_factory.dart';
import '../../services/storage/home_storage.dart';
import '../../services/storage/runtime_context_registry.dart';
import '../../services/workspace/repo_clone_service.dart';

/// Repo clone, install jobs and the skill registry config the shell boots
/// against one home plane.
typedef InstallWiring = ({
  RepoCloneCubit repoCloneCubit,
  InstallJobRegistry installJobRegistry,
  SkillRegistriesConfig skillRegistryConfig,
  SkillRegistryConfigService skillRegistryConfigService,
  SshProcessSpawner repoCloneSshSpawner,
});

/// Builds the repo clone cubit and the install job registry for [storage].
///
/// The SSH exec spawner is returned as well: the automation command runner
/// reuses it, so it stays one definition for both call sites.
Future<InstallWiring> wireInstallJobs({
  required HomeStorage storage,
  required SshProfileRepository sshProfiles,
  required SshClientFactory sshClientFactory,
  required RuntimeContextRegistry runtimeContexts,
  required RuntimeTarget Function() homeTarget,
  required ProgressActivityCubit progressActivity,
  required CliToolRegistry cliToolRegistry,
  required SessionPreferencesCubit sessionPreferences,
  required WorkspaceImportService importService,
  required AppUpdateService appUpdateService,
  required AppSettingsRepository appSettings,
  required bool deferHomePlaneLoads,
  required SshProfile? Function(String id) sshProfileById,
}) async {
  // Repo clone executor: one shared SSH exec spawner for both the clone
  // process (ProcessRunExecutor) and the host runner's context resolution
  // (mirrors WorkspaceRunPlatformFactory's spawner).
  Future<ProcessRunHandle> repoCloneSshSpawner({
    required String sshProfileId,
    required String shellCommand,
  }) async {
    final SshProfile? profile = await sshProfiles.findById(sshProfileId);
    if (profile == null) {
      throw StateError('SSH profile not found for this run target');
    }
    return sshClientFactory.startProcess(profile, shellCommand);
  }

  final repoCloneHostRunner = DefaultRepoCloneHostRunner(
    contextFor: runtimeContexts.forTarget,
    resolver: RunTargetResolver(homeTarget: homeTarget),
  );
  final repoCloneService = RepoCloneService(
    resolver: RunTargetResolver(homeTarget: homeTarget),
    executor: ProcessRunExecutor(sshSpawner: repoCloneSshSpawner),
    hostRunner: repoCloneHostRunner,
  );
  final repoCloneCubit = RepoCloneCubit(
    progressActivityCubit: progressActivity,
    service: repoCloneService,
    cleanupFs: repoCloneHostRunner.filesystemFor,
  );
  final installJobRunnerRegistry = InstallJobRunnerRegistry(
    runners: [
      CliInstallJobRunner(
        installerFactory: () => CliInstallerService(
          sshClientFactory: sshClientFactory,
          cliToolRegistry: cliToolRegistry,
          preferredNodePath: () => sessionPreferences.toolchainPath(
            SessionPreferences.toolchainNode,
          ),
        ),
        sshProfileById: sshProfileById,
        adapterResolver: (target) {
          for (final def in cliToolRegistry.launchable) {
            final installer = cliToolRegistry
                .capability<AcpSettingsCapability>(def.id)
                ?.adapterInstaller;
            if (installer != null && installer.adapterJobTarget == target) {
              return installer;
            }
          }
          return null;
        },
      ),
      ToolchainInstallJobRunner(),
      PackAcquireInstallJobRunner(),
      HubCloneInstallJobRunner(),
      FileTreeImportInstallJobRunner(importService: importService),
      AppUpdateInstallJobRunner(service: appUpdateService),
    ],
  );
  final installJobRegistry = InstallJobRegistry(
    progressCubit: progressActivity,
    runnerRegistry: installJobRunnerRegistry,
  );

  final skillRegistryConfigService = SkillRegistryConfigService(
    storage: storage,
    legacySkillsMpKeyReader: () => appSettings.loadSkillsMpApiKey(),
  );
  // Unreachable SSH home: skip the home-plane read; defaults keep the cubit
  // constructible and `SkillCubit.loadAll()` reloads the real config when
  // the deferred chain runs after connect.
  final skillRegistryConfig = deferHomePlaneLoads
      ? SkillRegistriesConfig.defaults()
      : await skillRegistryConfigService.load();

  return (
    repoCloneCubit: repoCloneCubit,
    installJobRegistry: installJobRegistry,
    skillRegistryConfig: skillRegistryConfig,
    skillRegistryConfigService: skillRegistryConfigService,
    repoCloneSshSpawner: repoCloneSshSpawner,
  );
}
