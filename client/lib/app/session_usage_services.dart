import 'dart:async';

import '../models/app_session.dart';
import '../models/session_usage.dart';
import '../models/session_usage_pricing.dart';
import '../models/team_config.dart';
import '../repositories/launch_profile_repository.dart';
import '../repositories/session_repository.dart';
import '../services/cli/registry/cli_tool_registry.dart';
import '../services/storage/home_storage.dart';
import '../services/usage/json_usage_cursor_store.dart';
import '../services/usage/json_usage_pricing_store.dart';
import '../services/usage/json_usage_store.dart';
import '../services/usage/session_usage_sync_service.dart';
import '../services/usage/team_pilot_usage_scan_target_provider.dart';
import '../services/usage/usage_pricing_store.dart';
import '../services/usage/usage_store.dart';
import '../services/usage/usage_sync_control.dart';

/// App-level wiring for agent CLI usage tracking.
///
/// Stores are reused for the current home plane; `JsonUsageStore` detects
/// external file changes by fingerprint. A home-plane swap rebuilds this
/// object. The page owns foreground scheduling; this object builds sync
/// handles and storage-maintenance operations.
final class SessionUsageServices {
  SessionUsageServices._({
    required this.syncAll,
    required this.startSync,
    required this.loadEvents,
    required this.loadPricing,
    required this.savePricing,
    required this.loadUsageStats,
    required this.compactUsage,
    required this.loadSessions,
    required this.loadTeams,
  });

  final Future<UsageSyncResult> Function() syncAll;
  final UsageSyncHandle Function() startSync;
  final Future<List<SessionUsageEvent>> Function() loadEvents;
  final Future<UsagePricingLoad> Function() loadPricing;
  final Future<void> Function(List<UsagePriceRule> rules) savePricing;
  final Future<UsageStoreStats> Function() loadUsageStats;
  final Future<UsageCompactResult> Function({int? retainAfterMs}) compactUsage;
  final Future<List<AppSession>> Function() loadSessions;
  final Future<List<TeamProfile>> Function() loadTeams;

  factory SessionUsageServices.forStorage({
    required HomeStorage storage,
    CliToolRegistry? registry,
    SessionRepository? sessions,
    LaunchProfileRepository? teams,
    Future<List<AppSession>> Function()? loadSessions,
    Future<List<TeamProfile>> Function()? loadTeams,
  }) {
    final registryForPlane = registry ?? CliToolRegistry.builtIn();

    // Default loaders construct a repository per call so they follow the
    // current plane; injected loaders take precedence.
    Future<List<AppSession>> defaultLoadSessions() =>
        (sessions ?? SessionRepository(storage: storage)).loadSessions();
    Future<List<TeamProfile>> defaultLoadTeams() =>
        (teams ?? LaunchProfileRepository(storage: storage)).loadTeamProfiles();
    final loadSessionsFn = loadSessions ?? defaultLoadSessions;
    final loadTeamsFn = loadTeams ?? defaultLoadTeams;

    const syncOverlapMs = 15 * 60 * 1000;
    const fullScanIntervalMs = 6 * 60 * 60 * 1000;
    int? lastSyncAtMs;
    int? lastFullScanAtMs;

    bool scanAllNow() {
      final lastFull = lastFullScanAtMs;
      return lastFull == null ||
          DateTime.now().millisecondsSinceEpoch - lastFull >=
              fullScanIntervalMs;
    }

    int? sinceNow() {
      final lastSync = lastSyncAtMs;
      return lastSync == null ? null : lastSync - syncOverlapMs;
    }

    String? planeKey;
    _PlaneUsageStores? planeStores;

    _PlaneUsageStores currentStores() {
      final key = '${storage.generation}:${storage.paths.usageEventsFile}';
      if (planeStores == null || planeKey != key) {
        planeKey = key;
        planeStores = _PlaneUsageStores(storage);
      }
      return planeStores!;
    }

    SessionUsageSyncService newSync(
      _PlaneUsageStores stores, {
      required bool scanAll,
      required int? sinceMs,
    }) => SessionUsageSyncService(
      targets: TeamPilotUsageScanTargetProvider(
        storage: storage,
        loadSessions: loadSessionsFn,
        loadTeams: loadTeamsFn,
        scanAll: scanAll,
        sinceMs: sinceMs,
      ),
      store: stores.store,
      cursors: stores.cursors,
      registry: registryForPlane,
    );

    void noteSync(UsageSyncResult result, {required bool wasFullScan}) {
      if (result.cancelled) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      lastSyncAtMs = now;
      if (wasFullScan && result.errors.isEmpty) lastFullScanAtMs = now;
    }

    Future<void> maybeCompact(_PlaneUsageStores stores) async {
      try {
        await stores.store.maybeCompact();
      } on Object {
        // Maintenance is best-effort; the sync result remains authoritative.
      }
    }

    UsageSyncHandle startSync() {
      final control = UsageSyncControl();
      final progress = StreamController<UsageSyncProgress>.broadcast(
        sync: true,
      );
      final stores = currentStores();
      final wasFullScan = scanAllNow();
      final service = newSync(
        stores,
        scanAll: wasFullScan,
        sinceMs: sinceNow(),
      );
      final done =
          Future.microtask(
                () =>
                    service.syncAll(control: control, onProgress: progress.add),
              )
              .then((result) async {
                noteSync(result, wasFullScan: wasFullScan);
                await maybeCompact(stores);
                return result;
              })
              .whenComplete(progress.close);
      return UsageSyncHandle(
        done: done,
        progress: progress.stream,
        cancel: control.cancel,
      );
    }

    Future<UsageSyncResult> syncAll() async {
      final stores = currentStores();
      final wasFullScan = scanAllNow();
      final result = await newSync(
        stores,
        scanAll: wasFullScan,
        sinceMs: sinceNow(),
      ).syncAll();
      noteSync(result, wasFullScan: wasFullScan);
      await maybeCompact(stores);
      return result;
    }

    return SessionUsageServices._(
      syncAll: syncAll,
      startSync: startSync,
      loadEvents: () => currentStores().store.readLatest(),
      loadPricing: () => currentStores().pricing.load(),
      savePricing: (rules) => currentStores().pricing.save(rules),
      loadUsageStats: () => currentStores().store.stats(),
      compactUsage: ({int? retainAfterMs}) =>
          currentStores().store.compact(retainAfterMs: retainAfterMs),
      loadSessions: loadSessionsFn,
      loadTeams: loadTeamsFn,
    );
  }
}

final class _PlaneUsageStores {
  _PlaneUsageStores(HomeStorage storage)
    : store = JsonUsageStore(
        fs: storage.fs,
        filePath: storage.paths.usageEventsFile,
      ),
      cursors = JsonUsageCursorStore(
        fs: storage.fs,
        filePath: storage.paths.usageCursorsFile,
      ),
      pricing = JsonUsagePricingStore(
        fs: storage.fs,
        filePath: storage.paths.usagePricingFile,
      );

  final JsonUsageStore store;
  final JsonUsageCursorStore cursors;
  final JsonUsagePricingStore pricing;
}
