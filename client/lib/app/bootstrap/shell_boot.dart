import 'dart:async';

import '../../cubits/ai_feature_settings_cubit.dart';
import '../../cubits/app_bootstrap_cubit.dart';
import '../../cubits/app_provider_cubit.dart';
import '../../cubits/chat_cubit.dart';
import '../../cubits/cli_presets_cubit.dart';
import '../../cubits/discovery_settings_cubit.dart';
import '../../cubits/extension_cubit.dart';
import '../../cubits/home_connection_cubit.dart';
import '../../cubits/launch_profile_cubit.dart';
import '../../cubits/layout_cubit.dart';
import '../../cubits/llm_config_cubit.dart';
import '../../cubits/mcp_cubit.dart';
import '../../cubits/plugin_cubit.dart';
import '../../cubits/shortcut_cubit.dart';
import '../../cubits/skill_cubit.dart';
import '../../cubits/ssh_connection_cubit.dart';
import '../../cubits/ssh_profile_cubit.dart';
import '../../models/runtime_target.dart';
import '../../models/ssh_profile.dart';
import '../../repositories/app_settings_repository.dart';
import '../../repositories/session_repository.dart';
import '../../services/app/connection_mode_service.dart';
import '../../services/automation/automation_scheduler.dart';
import '../../services/expert_hub/expert_hub_catalog.dart';
import '../../services/expert_hub/local_expert_store.dart';
import '../../services/home_workspace/home_workspace_ui_cache.dart';
import '../../services/perf/live_perf_driver.dart';
import '../../services/plugin/marketplace_shared_store.dart';
import '../../services/storage/home_invalidation_service.dart';
import '../../services/storage/home_storage.dart';
import '../../services/storage/runtime_context.dart';
import '../../utils/logging/logger.dart';
import '../../utils/ui/yield_ui_frame.dart';
import '../app_data_bootstrap.dart';
import 'home_plane_switch.dart';

/// Owns the app-data boot chain: the native warm-up, the deferred remote
/// (home-storage) boot replayed after an SSH home becomes reachable, and the
/// `bootstrapAppData` entry point `AppShell` runs after the shell is built.
///
/// The remote-boot completion/index/deferral flags live here and nowhere else:
/// a completed chain retires the retry surface, an in-flight guard coalesces
/// concurrent callers, and a failed chain leaves the flags unset so the next
/// reconnect retries it.
///
/// The rest of the shell's seams arrive as accessors. [homePlaneSwitch] and
/// [homeInvalidationService] are shell `late final`s assigned once the shell
/// graph is wired — the only reads happen inside [_runRemoteBootAfterConnectOnce],
/// i.e. strictly after construction. [homeConnectionCubit] is nullable because
/// the shell keeps the same nullable local for its construction-failure
/// teardown. No accessor points back at one of this controller's own methods.
class ShellBootController {
  ShellBootController({
    required this.homeStorage,
    required this.sshProfileCubit,
    required this.chatCubit,
    required this.sessionRepo,
    required this.layoutCubit,
    required this.teamCubit,
    required this.connectionModeService,
    required this.defaultTargetResolver,
    required this.sshProfileById,
    required this.bootstrapCubit,
    required this.homeIndexPrefetch,
    required this.notificationBootstrap,
    required this.shortcutCubit,
    required this.localExpertStore,
    required this.expertHubCatalog,
    required this.automationScheduler,
    required this.sshConnectionCubit,
    required this.homeConnectionCubit,
    required this.deferHomePlaneLoads,
    required this.boot,
    required this.appSettings,
    required this.appProviderCubit,
    required this.cliPresetsCubit,
    required this.aiFeatureSettingsCubit,
    required this.discoverySettingsCubit,
    required this.homeWorkspaceUiCache,
    required this.llmConfigCubit,
    required this.pluginCubit,
    required this.skillCubit,
    required this.mcpCubit,
    required this.extensionCubit,
    required this.hydrateManagedProviderData,
    required this.reinstallStorageContext,
    required this.homePlaneSwitch,
    required this.homeInvalidationService,
  });

  final HomeStorage homeStorage;
  final SshProfileCubit sshProfileCubit;
  final ChatCubit chatCubit;
  final SessionRepository sessionRepo;
  final LayoutCubit layoutCubit;
  final LaunchProfileCubit teamCubit;
  final ConnectionModeService connectionModeService;
  final RuntimeTarget Function() defaultTargetResolver;
  final SshProfile? Function(String id) sshProfileById;
  final AppBootstrapCubit? bootstrapCubit;
  final Future<void>? homeIndexPrefetch;
  final Future<void> Function() notificationBootstrap;
  final ShortcutCubit shortcutCubit;
  final LocalExpertStore localExpertStore;
  final ExpertHubCatalog expertHubCatalog;
  final AutomationScheduler automationScheduler;
  final SshConnectionCubit sshConnectionCubit;
  final HomeConnectionCubit? homeConnectionCubit;
  final bool deferHomePlaneLoads;
  final void Function(String phase) boot;
  final AppSettingsRepository appSettings;
  final AppProviderCubit appProviderCubit;
  final CliPresetsCubit cliPresetsCubit;
  final AiFeatureSettingsCubit aiFeatureSettingsCubit;
  final DiscoverySettingsCubit discoverySettingsCubit;
  final HomeWorkspaceUiCache homeWorkspaceUiCache;
  final LlmConfigCubit llmConfigCubit;
  final PluginCubit pluginCubit;
  final SkillCubit skillCubit;
  final McpCubit mcpCubit;
  final ExtensionCubit extensionCubit;
  final Future<void> Function() hydrateManagedProviderData;
  final Future<void> Function() reinstallStorageContext;
  final HomePlaneSwitchController Function() homePlaneSwitch;
  final HomeInvalidationService Function() homeInvalidationService;

  // Remote (home-storage) boot steps, deferred until the SSH home is known
  // reachable. A completed chain retires the retry surface; an in-flight
  // guard coalesces concurrent callers, and a failed chain leaves the flags
  // unset so the next reconnect retries it.
  var _remoteBootCompleted = false;
  var _remoteIndexBootstrapped = false;
  var _deferredHomePlaneLoadsDone = false;
  var _remoteShowOnboarding = false;
  Future<bool>? _remoteBootInFlight;

  Future<void> reconnectHomeSshIfNeeded() async {
    final home = defaultTargetResolver();
    final pid = home.sshProfileId;
    if (home.kind != RuntimeKind.ssh || pid == null || pid.isEmpty) return;
    await sshConnectionCubit.syncProfiles(sshProfileCubit.state.profiles);
    unawaited(sshConnectionCubit.connect(pid));
  }

  /// Background one-time migration: replace stale per-session marketplace
  /// clones with a symlink to the shared flavor dir (see
  /// [MarketplaceSharedStore]). Skips currently-open sessions; non-fatal.
  Future<void> _sweepStaleMarketplaceClones() async {
    try {
      await MarketplaceSharedStore(
        fs: homeStorage.fs,
        teampilotRoot: homeStorage.paths.basePath,
      ).sweepAll(
        workspaceIds: [
          for (final workspace in chatCubit.state.workspaces)
            workspace.workspaceId,
        ],
        activeSessionKeys: {
          for (final tab in chatCubit.tabStore.openTabs) tab.sessionId,
        },
      );
    } on Object catch (e, st) {
      appLogger.w('[boot] marketplaceCloneSweep failed: $e\n$st');
    }
  }

  /// Warm the shell-hosted config + auxiliary data and resolve onboarding.
  /// Shared by the native path and the remote (post-connect) boot so both
  /// stay identical; returns `showOnboardingWizard`.
  Future<bool> _warmShellAndPrepareInteractive() async {
    await yieldUiFrame();
    // Managed Provider cache hydration is deliberately background work. The
    // shell can paint while the global Cubits transition from initial to
    // ready, and the Cubit load methods keep repeated bootstrap calls single-
    // flight.
    unawaited(hydrateManagedProviderData());
    boot(
      'bootstrapAppData index ready '
      'workspaces=${chatCubit.state.workspaces.length} '
      '(sessions load on demand)',
    );
    unawaited(_sweepStaleMarketplaceClones());
    bootstrapCubit?.beginWarmAuxiliary();
    // Only host config the home shell renders stays on the splash path.
    // Model catalogs are composer-only, and the rest (plugins, skills, MCP,
    // extensions, team resource syncs, llmConfig) loads in the background
    // behind its own loading states.
    await AppDataBootstrap.warmShellConfig(
      boot: boot,
      appProviderCubit: appProviderCubit,
    );
    unawaited(() async {
      try {
        await AppDataBootstrap.warmAuxiliaryData(
          boot: boot,
          llmConfigCubit: llmConfigCubit,
          appProviderCubit: appProviderCubit,
          teamCubit: teamCubit,
          pluginCubit: pluginCubit,
          skillCubit: skillCubit,
          mcpCubit: mcpCubit,
          extensionCubit: extensionCubit,
        );
      } on Object catch (error, stackTrace) {
        appLogger.w(
          '[boot] auxiliary warm-up failed',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }());
    return AppDataBootstrap.prepareInteractiveShell(
      boot: boot,
      appSettings: appSettings,
      sshProfileCubit: sshProfileCubit,
      cliPresetsCubit: cliPresetsCubit,
      aiFeatureSettingsCubit: aiFeatureSettingsCubit,
      discoverySettingsCubit: discoverySettingsCubit,
      homeWorkspaceUiCache: homeWorkspaceUiCache,
      storage: homeStorage,
      workspaces: chatCubit.state.workspaces,
    );
  }

  Future<bool> _runRemoteBootAfterConnectOnce() async {
    // A first-ever-unreachable SSH home has no persisted `lastHome`, so boot
    // fell back to the native control plane (see `resolveCached`). Never
    // write the remote index/config into that plane: it would silently
    // diverge from the home the user believes they are on. The mismatch
    // self-heals on the next launch, when the live home resolves before boot.
    if (defaultTargetResolver().kind == RuntimeKind.ssh &&
        homeStorage.context.mode != StorageBackendMode.ssh) {
      appLogger.w(
        '[boot] home storage plane mismatch; skipping remote boot until restart',
      );
      return _remoteShowOnboarding;
    }
    // Home-plane reads skipped during an unreachable splash (they are not
    // shown while the connection page is up). Run them now that the
    // transport is live.
    if (deferHomePlaneLoads) {
      try {
        await notificationBootstrap();
      } on Object catch (error, stackTrace) {
        // Notifications are off the shell's critical path. Keep warming the
        // rest; `retryableMemo` clears the failed attempt, so the next
        // reconnect tries it again.
        appLogger.w(
          '[boot] notification bootstrap failed after reconnect',
          error: error,
          stackTrace: stackTrace,
        );
      }
      if (!_deferredHomePlaneLoadsDone) {
        await shortcutCubit.load();
        await localExpertStore.migrateLegacyLayout();
        await localExpertStore.ensureIndexLoaded();
        // The boot-time catalog warm cached a snapshot without the local
        // templates; invalidate so the next read includes them.
        expertHubCatalog.invalidate();
        _deferredHomePlaneLoadsDone = true;
      }
    }
    // Deliberately not `bootstrapCubit.state.homeIndexReady`: that getter is
    // also true once the phase is `ready`, which is exactly the state a
    // deferred boot leaves behind, and hot recovery must still load the
    // index it skipped.
    if (!_remoteIndexBootstrapped) {
      boot('awaiting remote home index snapshots');
      try {
        await homeIndexPrefetch;
        await AppDataBootstrap.bootstrapHomeIndex(
          boot: boot,
          sshProfileCubit: sshProfileCubit,
          teamCubit: teamCubit,
          chatCubit: chatCubit,
          sessionRepo: sessionRepo,
          layoutCubit: layoutCubit,
          isSshMode: connectionModeService.isRemoteWorkPlane,
          homeSshProfileId: defaultTargetResolver().sshProfileId,
          sshProfileExists: (id) => sshProfileById(id) != null,
          // buildAppShell just materialized the home context from the same
          // on-disk profiles this bootstrap reloads, so a rebind here would
          // only repeat the path probe (~0.7s over SSH) with no new input.
          reinstallSshHome: false,
          // Not invoked while the flag above is false. Kept bracketed:
          // a reinstall outside the invalidation service's reload would
          // publish a swap that echoes back as an external home switch and
          // schedules a duplicate full bootstrap.
          reinstallStorageContext: () => homeInvalidationService()
              .runSelfInitiatedSwap(reinstallStorageContext),
          storage: homeStorage,
          home: defaultTargetResolver(),
          expertHubCatalog: expertHubCatalog,
        );
        await homePlaneSwitch().persistSshHomePathCacheIfLive();
        _remoteIndexBootstrapped = true;
        bootstrapCubit?.markHomeIndexReady();
      } on Object catch (error, stackTrace) {
        appLogger.w(
          '[boot] remote home index bootstrap failed',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
    _remoteShowOnboarding = await _warmShellAndPrepareInteractive();
    // Completed only once the whole chain succeeded: a transient failure
    // after a flaky reconnect must remain retryable by the next onConnected
    // (the status is `connected`, so the user has no manual retry surface).
    _remoteBootCompleted = _remoteIndexBootstrapped;
    return _remoteShowOnboarding;
  }

  Future<bool> runRemoteBootAfterConnect() {
    if (_remoteBootCompleted) return Future.value(_remoteShowOnboarding);
    final inFlight = _remoteBootInFlight;
    if (inFlight != null) return inFlight;
    final future = _runRemoteBootAfterConnectOnce();
    _remoteBootInFlight = future;
    return future.whenComplete(() {
      if (identical(_remoteBootInFlight, future)) {
        _remoteBootInFlight = null;
      }
    });
  }

  Future<void> bootstrapAppData() async {
    final connected =
        homeConnectionCubit?.state.status == HomeConnectionStatus.connected;
    final remoteWorkPlane = connectionModeService.isRemoteWorkPlane;
    // An unreachable SSH home defers every home-storage read: the shell must
    // paint the connection page without waiting on a dead transport. The
    // deferred chain runs once on the first successful (re)connect.
    final deferRemoteBoot = remoteWorkPlane && !connected;
    var showOnboarding = false;
    if (!deferRemoteBoot) {
      await notificationBootstrap();
      final indexReady = bootstrapCubit?.state.homeIndexReady ?? false;
      if (!indexReady) {
        bootstrapCubit?.beginHomeIndex();
      }
      boot('bootstrapAppData start');
      if (remoteWorkPlane) {
        showOnboarding = await runRemoteBootAfterConnect();
      } else {
        if (!indexReady) {
          boot('awaiting home index snapshots');
          await homeIndexPrefetch;
          await AppDataBootstrap.hydrateNativeHomeIndex(
            boot: boot,
            teamCubit: teamCubit,
            chatCubit: chatCubit,
            sessionRepo: sessionRepo,
            layoutCubit: layoutCubit,
            storage: homeStorage,
            home: defaultTargetResolver(),
            expertHubCatalog: expertHubCatalog,
          );
          bootstrapCubit?.markHomeIndexReady();
        }
        showOnboarding = await _warmShellAndPrepareInteractive();
      }
    } else {
      // The device-local SSH catalog is the one boot read that must survive
      // an unreachable home: the connection page lists it to switch/recover,
      // and it never lives on the home plane. Deferring it together with the
      // remote boot left 「切换连接」 empty even though remote-targets.json
      // held every saved target. It is a local file read, so awaiting it
      // cannot stall on the dead transport.
      try {
        await sshProfileCubit.load(discoverRemoteCli: false);
      } on Object catch (error, stackTrace) {
        appLogger.w(
          '[boot] device-local SSH catalog load failed while the home was '
          'unreachable',
          error: error,
          stackTrace: stackTrace,
        );
      }
      boot('bootstrapAppData deferred: home unreachable');
    }
    // Unconditional: both the connected and the deferred (unreachable) path
    // must finish boot so StartupGate can render the connection page.
    bootstrapCubit?.markAppReady(showOnboardingWizard: showOnboarding);
    LivePerfDriver.instance?.markAppReady();
    boot('bootstrapAppData complete');
    if (connected) {
      // Team-generation jobs are not auto-resumed at cold start. Incomplete
      // builder/destination sessions reconnect only when the user opens them.
      // Never on the splash path: the shell is already marked ready, so a
      // failure here is logged rather than surfaced as a boot error.
      unawaited(
        reconnectHomeSshIfNeeded().catchError((
          Object error,
          StackTrace stackTrace,
        ) {
          appLogger.w(
            '[boot] home ssh resume failed',
            error: error,
            stackTrace: stackTrace,
          );
        }),
      );
    }
    automationScheduler.start();
  }
}
