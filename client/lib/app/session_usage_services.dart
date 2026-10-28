import 'dart:async';

import 'package:http/http.dart' as http;

import '../models/app_session.dart';
import '../models/cursor_usage_import.dart';
import '../models/session_usage.dart';
import '../models/session_usage_pricing.dart';
import '../models/session_usage_sync_state.dart';
import '../models/team_config.dart';
import '../repositories/launch_profile_repository.dart';
import '../repositories/session_repository.dart';
import '../services/cli/cursor/provider/cursor_usage_auth_resolver.dart';
import '../services/cli/registry/cli_tool_registry.dart';
import '../services/storage/home_storage.dart';
import '../services/usage/json_usage_cursor_store.dart';
import '../services/usage/json_usage_pricing_store.dart';
import '../services/usage/cursor_usage_import_store.dart';
import '../services/usage/cursor_usage_sync_service.dart';
import '../services/usage/json_usage_store.dart';
import '../services/usage/json_usage_sync_state_store.dart';
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
    required this.startFullSync,
    required this.loadEvents,
    required this.loadPricing,
    required this.savePricing,
    required this.loadUsageStats,
    required this.compactUsage,
    required this.loadSessions,
    required this.loadTeams,
    required this.loadCursorStatus,
    required this.importCursorCsv,
    required this.syncCursorUsage,
    required this.clearCursorUsage,
  });

  final Future<UsageSyncResult> Function() syncAll;
  final UsageSyncHandle Function() startSync;
  final UsageSyncHandle Function() startFullSync;
  final Future<List<SessionUsageEvent>> Function() loadEvents;
  final Future<UsagePricingLoad> Function() loadPricing;
  final Future<void> Function(List<UsagePriceRule> rules) savePricing;
  final Future<UsageStoreStats> Function() loadUsageStats;
  final Future<UsageCompactResult> Function({int? retainAfterMs}) compactUsage;
  final Future<List<AppSession>> Function() loadSessions;
  final Future<List<TeamProfile>> Function() loadTeams;
  final Future<CursorUsageImportStatus> Function() loadCursorStatus;
  final Future<CursorUsageImportResult> Function(String text) importCursorCsv;
  final Future<CursorUsageImportResult> Function() syncCursorUsage;
  final Future<void> Function() clearCursorUsage;

  factory SessionUsageServices.forStorage({
    required HomeStorage storage,
    CliToolRegistry? registry,
    SessionRepository? sessions,
    LaunchProfileRepository? teams,
    Future<List<AppSession>> Function()? loadSessions,
    Future<List<TeamProfile>> Function()? loadTeams,
    http.Client? cursorHttpClient,
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

    String? planeKey;
    _PlaneUsageStores? planeStores;

    _PlaneUsageStores currentStores() {
      final key = '${storage.generation}:${storage.paths.usageEventsFile}';
      if (planeStores == null || planeKey != key) {
        planeKey = key;
        planeStores = _PlaneUsageStores(
          storage,
          cursorHttpClient: cursorHttpClient,
        );
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

    Future<void> noteSync(
      _PlaneUsageStores stores,
      UsageSyncResult result, {
      required bool wasFullScan,
      required UsageSyncState previous,
    }) async {
      if (result.cancelled) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      await stores.syncState.save(
        UsageSyncState(
          lastFullScanAtMs: wasFullScan && result.errors.isEmpty
              ? now
              : previous.lastFullScanAtMs,
          lastSyncAtMs: now,
        ),
      );
    }

    Future<void> maybeCompact(_PlaneUsageStores stores) async {
      try {
        await stores.store.maybeCompact();
      } on Object {
        // Maintenance is best-effort; the sync result remains authoritative.
      }
    }

    Future<UsageSyncResult> runSync({
      required bool full,
      UsageSyncControl? control,
      void Function(UsageSyncProgress)? onProgress,
    }) async {
      final stores = currentStores();
      final previous = await stores.syncState.load();
      final wasFullScan = full || !previous.hasBaseline;
      final sinceMs = previous.lastSyncAtMs == null
          ? null
          : previous.lastSyncAtMs! - syncOverlapMs;
      final result = await newSync(
        stores,
        scanAll: wasFullScan,
        sinceMs: sinceMs,
      ).syncAll(control: control, onProgress: onProgress);
      await noteSync(
        stores,
        result,
        wasFullScan: wasFullScan,
        previous: previous,
      );
      await maybeCompact(stores);
      return result;
    }

    UsageSyncHandle startHandle({required bool full}) {
      final control = UsageSyncControl();
      final progress = StreamController<UsageSyncProgress>.broadcast(
        sync: true,
      );
      final done = Future.microtask(
        () => runSync(full: full, control: control, onProgress: progress.add),
      ).whenComplete(progress.close);
      return UsageSyncHandle(
        done: done,
        progress: progress.stream,
        cancel: control.cancel,
      );
    }

    UsageSyncHandle startSync() => startHandle(full: false);

    UsageSyncHandle startFullSync() => startHandle(full: true);

    Future<UsageSyncResult> syncAll() => runSync(full: false);

    Future<List<SessionUsageEvent>> loadEvents() async {
      final stores = currentStores();
      final base = await stores.store.readLatest();
      final imported = await stores.cursorImport.loadEvents();
      if (imported.isEmpty) return base;
      final byId = {for (final event in base) event.requestId: event};
      for (final event in imported) {
        byId[event.requestId] = event;
      }
      final merged = byId.values.toList(growable: false);
      merged.sort((a, b) => a.timestampMs.compareTo(b.timestampMs));
      return merged;
    }

    return SessionUsageServices._(
      syncAll: syncAll,
      startSync: startSync,
      startFullSync: startFullSync,
      loadEvents: loadEvents,
      loadPricing: () => currentStores().pricing.load(),
      savePricing: (rules) => currentStores().pricing.save(rules),
      loadUsageStats: () => currentStores().store.stats(),
      compactUsage: ({int? retainAfterMs}) =>
          currentStores().store.compact(retainAfterMs: retainAfterMs),
      loadSessions: loadSessionsFn,
      loadTeams: loadTeamsFn,
      loadCursorStatus: () => currentStores().cursorSync.status(),
      importCursorCsv: (text) => currentStores().cursorSync.importCsv(text),
      syncCursorUsage: () => currentStores().cursorSync.sync(),
      clearCursorUsage: () => currentStores().cursorSync.clear(),
    );
  }
}

final class _PlaneUsageStores {
  _PlaneUsageStores(HomeStorage storage, {http.Client? cursorHttpClient})
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
      ),
      syncState = JsonUsageSyncStateStore(
        fs: storage.fs,
        filePath: storage.paths.usageSyncStateFile,
      ) {
    cursorImport = CursorUsageImportStore(
      fs: storage.fs,
      filePath: storage.paths.usageCursorImportFile,
    );
    cursorSync = CursorUsageSyncService(
      store: cursorImport,
      auth: CursorUsageAuthResolver(
        fs: storage.fs,
        basePath: storage.paths.basePath,
        home: storage.home,
      ),
      httpClient: cursorHttpClient,
    );
  }

  final JsonUsageStore store;
  final JsonUsageCursorStore cursors;
  final JsonUsagePricingStore pricing;
  final JsonUsageSyncStateStore syncState;
  late final CursorUsageImportStore cursorImport;
  late final CursorUsageSyncService cursorSync;
}
