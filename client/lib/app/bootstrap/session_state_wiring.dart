import '../../cubits/app_bootstrap_cubit.dart';
import '../../cubits/cli_presets_cubit.dart';
import '../../cubits/llm_config_cubit.dart';
import '../../cubits/session_preferences_cubit.dart';
import '../../cubits/ssh_profile_cubit.dart';
import '../../models/runtime_target.dart';
import '../../models/session_preferences.dart';
import '../../models/ssh_profile.dart';
import '../../repositories/app_settings_repository.dart';
import '../../repositories/cli_presets_repository.dart';
import '../../repositories/extension_repository.dart';
import '../../repositories/launch_profile_repository.dart';
import '../../repositories/session_repository.dart';
import '../../repositories/skill_repository.dart';
import '../../repositories/ssh_profile_repository.dart';
import '../../repositories/workspace_project_config_repository.dart';
import '../../services/app/connection_mode_service.dart';
import '../../services/chat/session/session_lifecycle_service.dart';
import '../../services/cli/registry/cli_tool_registry.dart';
import '../../services/extension/builtin_manifests.dart';
import '../../services/ssh/ssh_client_factory.dart';
import '../../services/ssh/ssh_connection_gate.dart';
import '../../services/storage/home_storage.dart';
import '../../services/storage/runtime_context_registry.dart';
import '../../utils/logging/logger.dart';
import '../home_index_prefetch.dart';

/// LLM config cubit plus the launch-time config-path override it decides.
typedef LlmConfigWiring = ({
  LlmConfigCubit cubit,
  String? Function() pathOverrideForLaunch,
});

/// Session lifecycle service plus the session repository built on it.
typedef SessionStateWiring = ({
  SessionLifecycleService sessionLifecycleService,
  SessionRepository sessionRepo,
});

/// Launch-profile repository bound to one home plane.
typedef IdentityWiring = ({LaunchProfileRepository identityRepository});

/// Home index prefetch future the boot sequence may await.
typedef HomeIndexPrefetchWiring = ({Future<void>? homeIndexPrefetch});

/// Builds the LLM config cubit for [storage] and its path override closure.
LlmConfigWiring wireLlmConfig({
  required AppSettingsRepository appSettings,
  required HomeStorage storage,
  required SessionPreferencesCubit sessionPreferences,
  required ConnectionModeService Function() connectionMode,
  required SshProfileCubit Function() sshProfiles,
  required SshClientFactory sshClientFactory,
}) {
  final cubit = LlmConfigCubit(
    appSettings: appSettings,
    storage: storage,
    executableResolver: () => sessionPreferences.resolveExecutable(),
    isSshMode: () => connectionMode().isSshMode,
    sshProfileResolver: () => sshProfiles().state.selectedProfile,
    sshClientFactory: sshClientFactory,
    sshWorkingDirectoryResolver: () =>
        sessionPreferences.state.preferences.defaultSshWorkingDirectory,
  );

  String? pathOverrideForLaunch() {
    final s = cubit.state;
    final path = s.effectiveConfigPath.trim();
    if (path.isEmpty) return null;
    if (connectionMode().isSshMode) return path;
    return s.isUsingCustomPath ? path : null;
  }

  return (cubit: cubit, pathOverrideForLaunch: pathOverrideForLaunch);
}

/// Builds the launch-profile repository for [storage].
IdentityWiring wireIdentityRepository({required HomeStorage storage}) {
  final identityRepository = LaunchProfileRepository(storage: storage);
  return (identityRepository: identityRepository);
}

/// Builds the session lifecycle service and session repository for one home
/// plane.
///
/// [identityRepository] is a getter because the shell assigns its
/// `late final` field before calling this and reads it lazily inside the
/// lifecycle service.
SessionStateWiring wireSessionState({
  required HomeStorage storage,
  required RuntimeContextRegistry runtimeContexts,
  required RuntimeTarget Function() homeTarget,
  required ExtensionRepository extensionRepository,
  required WorkspaceProjectConfigRepository workspaceConfig,
  required CliPresetsRepository cliPresets,
  required CliToolRegistry cliToolRegistry,
  required SkillRepository skillRepository,
  required SessionPreferencesCubit sessionPreferences,
  required SshProfileRepository sshProfiles,
  required CliPresetsCubit Function() cliPresetsCubit,
  required SshProfile? Function(String id) sshProfileById,
  required LaunchProfileRepository Function() identityRepository,
}) {
  final sessionLifecycleService = SessionLifecycleService(
    storage: storage,
    storageRootsResolver: () async => storage.context,
    catalogContextResolver: () async => runtimeContexts.home(),
    homeTarget: homeTarget,
    // P2: launch resolves the work-plane on the workspace's target machine.
    workContextResolver: runtimeContexts.forTarget,
    loadEnabledExtensionIds: ({teamId, workspaceId}) async {
      final trimmedTeamId = teamId?.trim() ?? '';
      if (trimmedTeamId.isNotEmpty) {
        return extensionRepository.effectiveEnabledIds(trimmedTeamId);
      }
      final trimmedWorkspaceId = workspaceId?.trim() ?? '';
      if (trimmedWorkspaceId.isNotEmpty) {
        final config = await workspaceConfig.load(trimmedWorkspaceId);
        final global = (await extensionRepository.load()).globalEnabled;
        return {
          for (final manifest in builtInExtensionManifests())
            if (config.effectiveExtensionEnabled(
              extensionId: manifest.id,
              globalEnabled: global,
            ))
              manifest.id,
        };
      }
      return (await extensionRepository.load(forceReload: true))
          .globalEnabled;
    },
    cliToolRegistry: cliToolRegistry,
    cliExecutableResolver: sessionPreferences.resolveExecutable,
    toolchainNodeResolver: () => sessionPreferences.resolveToolchainExecutable(
      SessionPreferences.toolchainNode,
      '',
    ),
    identityRepository: identityRepository(),
    loadInstalledSkills: () => skillRepository.loadInstalled(),
    cliPresetsRepository: cliPresets,
    loadPresets: () => cliPresetsCubit().state.presets,
    projectConfigRepository: workspaceConfig,
    sshProfileById: sshProfileById,
  );
  final sessionRepo = SessionRepository(
    storage: storage,
    lifecycleService: sessionLifecycleService,
  );
  return (
    sessionLifecycleService: sessionLifecycleService,
    sessionRepo: sessionRepo,
  );
}

/// Starts the home index prefetch and binds it to the boot sequence.
///
/// [connectionMode], [sessions] and [identities] are getters: the shell calls
/// this right after assigning the repositories, and the prefetch closure runs
/// later against whatever home plane is active then.
HomeIndexPrefetchWiring wireHomeIndexPrefetch({
  required AppBootstrapCubit? bootstrapCubit,
  required ConnectionModeService Function() connectionMode,
  required Future<void>? nativePrefetch,
  required SessionRepository Function() sessions,
  required LaunchProfileRepository Function() identities,
  required void Function(String) boot,
}) {
  boot('prefetching home index snapshots');
  bootstrapCubit?.beginHomeIndex();
  Future<void> prefetchHomeIndex() async {
    try {
      await Future.wait([
        sessions().loadWorkspacesIndex(),
        identities().loadAll(),
      ]);
    } on Object catch (error, stackTrace) {
      if (isSshProfileDown(error)) {
        appLogger.d(
          '[boot] home index prefetch waiting for home transport',
          error: error,
          stackTrace: stackTrace,
        );
        return;
      }
      appLogger.w(
        '[boot] home index prefetch failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  if (connectionMode().isRemoteWorkPlane && nativePrefetch != null) {
    boot('ignoring native-path home index prefetch (remote home)');
  }
  final homeIndexPrefetch = bindHomeIndexPrefetch(
    isRemoteWorkPlane: connectionMode().isRemoteWorkPlane,
    nativePathPrefetch: nativePrefetch,
    boundHomePrefetch: prefetchHomeIndex,
  );
  return (homeIndexPrefetch: homeIndexPrefetch);
}
