import 'dart:io';

import '../../models/runtime_target.dart';
import '../../models/ssh_profile.dart';
import '../../repositories/ssh_credential_store.dart';
import '../../repositories/ssh_profile_repository.dart';
import '../../services/chat/conversation/history/ai_history_loader.dart';
import '../../services/editor/markdown_network_image_store.dart';
import '../../services/home_workspace/home_workspace_ui_cache.dart';
import '../../services/shared_state/device_id_store.dart';
import '../../services/shared_state/shared_state_identity.dart';
import '../../services/ssh/ssh_client_factory.dart';
import '../../services/ssh/ssh_transport_close.dart';
import '../../services/ssh/tcp_reachability_probe.dart';
import '../../services/storage/app_paths.dart';
import '../../services/storage/device_local_control_plane.dart';
import '../../services/storage/home_connect_attempt.dart';
import '../../services/storage/home_storage.dart';
import '../../services/storage/runtime_context_registry.dart';
import '../../services/storage/runtime_context_resolver.dart';
import '../../services/storage/runtime_target_registry.dart';
import '../../services/termux/termux_config.dart';
import '../../services/termux/termux_config_store.dart';
import '../../services/vault/home_vault_service.dart';

/// The home-control plane: the target registry + per-target context registry,
/// the home connect result the shell seeds its cubit with, the home [HomeStorage]
/// facade, and the home-plane vault scope.
typedef HomePlaneWiring = ({
  RuntimeTargetRegistry homeTargetRegistry,
  RuntimeContextRegistry runtimeContextRegistry,
  HomeConnectAttempt homeAttempt,
  HomeConnectResult initialHome,
  bool deferHomePlaneLoads,
  String? homeProfileId,
  bool isSshHome,
  SshProfile? homeSshProfile,
  HomeStorage homeStorage,
  HomeVaultScope scope,
  HomeWorkspaceUiCache homeWorkspaceUiCache,
});

/// Builds the home plane and resolves its first context.
///
/// Mutable shell state stays shell-owned and arrives as accessors, never as
/// copies: [homeTarget] reads the live home target (it changes on a home
/// switch), [termuxConfig]/[setTermuxConfig] reach the shell's termux config
/// cache, and [historyLoader] is assigned after this call so the registry's
/// eviction hook still clears the live loader.
///
/// [boot] is the shell's phase logger; each call stays at the point it used to
/// log inline, so the stopwatch phases report the same order.
Future<HomePlaneWiring> wireHomePlane({
  required SshProfileRepository sshProfileRepo,
  required SshProfile? Function(String profileId) sshProfileById,
  SshProfile? Function(String profileId)? workProfileById,
  required RuntimeTarget Function(String id) homeTargetFromId,
  required RuntimeTarget Function() homeTarget,
  required TermuxConfigStore termuxConfigStore,
  required TermuxConfig? Function() termuxConfig,
  required void Function(TermuxConfig config) setTermuxConfig,
  required SshClientFactory sshClientFactory,
  required AiHistoryLoader? Function() historyLoader,
  required String nativeAppDataPath,
  required String defaultWorkspaceDirectory,
  required void Function(String phase) boot,
}) async {
  // Home-target palette: device-local home-binding catalog (A source),
  // read-only. It must never reconcile the workload `targets.json` — that file
  // belongs to the workspace registry bound to the B source in buildAppShell.
  final homeTargetRegistry = RuntimeTargetRegistry(
    sshProfileRepo: sshProfileRepo,
    isWindows: Platform.isWindows,
    isAndroid: Platform.isAndroid,
    hasTermuxConfig: () => termuxConfig() != null,
  );

  // P2: de-singleton. One resolver + a per-target context registry. The home
  // context (control plane) is materialized once and published on HomeStorage;
  // work-plane contexts are resolved lazily per workspace target id.
  final runtimeContextResolver = RuntimeContextResolver(
    sshClientFactory: sshClientFactory,
    nativeAppDataPath: nativeAppDataPath,
    nativeHome:
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'],
    nativeCwd: defaultWorkspaceDirectory,
  );
  final runtimeContextRegistry = RuntimeContextRegistry(
    resolver: runtimeContextResolver,
    homeTarget: homeTarget(),
    sshProfileById: sshProfileById,
    termuxPathCache: () {
      final cfg = termuxConfig();
      if (cfg == null) {
        return (home: null, appDataRoot: null);
      }
      return (home: cfg.lastHome, appDataRoot: cfg.lastAppDataRoot);
    },
    onEvict: (targetId) async {
      final pid =
          homeTargetFromId(targetId).sshProfileId ?? sshProfileIdOfId(targetId);
      if (pid != null) {
        sshClientFactory.disconnectProfile(
          pid,
          reason: SshTransportCloseReason.runtimeContextEvicted,
        );
      }
      // v1: clear all history memory cache on work-plane drop.
      historyLoader()?.clearCache();
    },
  );
  boot('installing home runtime context');
  final ensureHomeSw = Stopwatch()..start();
  // SSH homes get one bounded attempt (TCP probe + time-boxed resolve) so an
  // unreachable/slow host cannot hold the splash indefinitely. Every other
  // home kind keeps the existing unbounded resolve.
  final homeProfileId = homeTarget().sshProfileId;
  final isSshHome =
      homeTarget().kind == RuntimeKind.ssh &&
      homeProfileId != null &&
      homeProfileId.isNotEmpty;
  final homeSshProfile = isSshHome ? sshProfileById(homeProfileId) : null;
  // One bounded attempt factory reused by boot and every later retry: it reads
  // the registry's CURRENT home target, so it follows [setHomeTarget] too.
  final homeAttempt = HomeConnectAttempt(
    probe: const SocketTcpReachabilityProbe(),
    resolve: () async {
      await runtimeContextRegistry.ensureHome();
      return runtimeContextRegistry.home();
    },
    cacheContext: runtimeContextRegistry.ensureHomeCached,
    profileById: sshProfileById,
  );
  HomeConnectResult initialHome;
  if (isSshHome) {
    initialHome = await homeAttempt.run(homeProfileId);
  } else {
    await runtimeContextRegistry.ensureHome();
    initialHome = HomeConnectResult.connected(runtimeContextRegistry.home());
  }
  boot('home runtime context ensured +${ensureHomeSw.elapsedMilliseconds}ms');
  // A failed attempt already carries the cached-path context, so the shell can
  // be built without waiting for any network round-trip.
  final homeCtx =
      initialHome.context ?? await runtimeContextRegistry.ensureHomeCached();
  // True when an SSH home failed its first bounded attempt. Home-plane reads
  // are then deferred to the post-connect chain: with no warm client every one
  // of them starts a fresh storage open bounded by SshStorageIo.ioTimeout, and
  // awaiting them here would reintroduce the splash stall this task removes.
  final deferHomePlaneLoads = isSshHome && !initialHome.reachable;
  final cfg = termuxConfig();
  if (homeTarget().kind == RuntimeKind.termux &&
      cfg != null &&
      !homeCtx.pathsFromCache) {
    final updated = cfg.copyWith(
      lastHome: homeCtx.home,
      lastAppDataRoot: homeCtx.appDataRoot,
    );
    setTermuxConfig(updated);
    await termuxConfigStore.save(updated);
  }
  // Versioned, drain-safe home facade: home swaps publish through it and the
  // outgoing context is retired (registry evict → drain-safe SSH disconnect)
  // only after the new context is live. Every control-plane consumer receives
  // it via constructor injection (or the RepositoryProvider in main.dart).
  final homeStorage = HomeStorage(
    homeCtx,
    retire: (old) => runtimeContextRegistry.disposeContext(old),
  );
  // Shared-state stamps are device-scoped, so the id lives in the device
  // plane and never travels through the home plane.
  final deviceId = await DeviceIdStore(
    fs: deviceLocalHomeStorage(nativeAppDataPath).fs,
    path: AppPaths.pathContextForDataRoot(nativeAppDataPath)
        .join(nativeAppDataPath, 'shared-state', 'device-id'),
  ).loadOrCreate();
  SharedStateIdentity.configure(deviceId: deviceId);
  final homeWorkspaceUiCache = HomeWorkspaceUiCache(storage: homeStorage);
  // Disk cache for markdown network images lives under the home
  // <teampilotRoot>/cache; bind it before any editor surface loads a badge.
  MarkdownNetworkImageStore.storageHome = homeStorage;
  boot(
    'home context installed '
    '(${homeStorage.context.mode}, home=${homeTarget().id}, '
    'root=${homeStorage.appDataRoot})',
  );

  // Home-plane business vault. SSH login credentials remain in the device
  // vault; everything else is written to / read from <home>/vault/.
  final scope = HomeVaultScope(
    storage: homeStorage,
    keyStore: const FlutterSecureKeyValueStore(),
  );

  return (
    homeTargetRegistry: homeTargetRegistry,
    runtimeContextRegistry: runtimeContextRegistry,
    homeAttempt: homeAttempt,
    initialHome: initialHome,
    deferHomePlaneLoads: deferHomePlaneLoads,
    homeProfileId: homeProfileId,
    isSshHome: isSshHome,
    homeSshProfile: homeSshProfile,
    homeStorage: homeStorage,
    scope: scope,
    homeWorkspaceUiCache: homeWorkspaceUiCache,
  );
}
