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
import '../services/usage/usage_sync_control.dart';

/// App-level wiring for agent CLI usage tracking.
///
/// Stores, loaders, and the sync service are constructed per call from the
/// current [HomeStorage] context, so a home-plane swap is picked up without
/// rebuilding this object. The page owns foreground scheduling; this object
/// only builds one-shot scans and handles.
final class SessionUsageServices {
  SessionUsageServices._({
    required this.syncAll,
    required this.startSync,
    required this.loadEvents,
    required this.loadPricing,
    required this.savePricing,
    required this.loadSessions,
    required this.loadTeams,
  });

  final Future<UsageSyncResult> Function() syncAll;
  final UsageSyncHandle Function() startSync;
  final Future<List<SessionUsageEvent>> Function() loadEvents;
  final Future<UsagePricingLoad> Function() loadPricing;
  final Future<void> Function(List<UsagePriceRule> rules) savePricing;
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

    JsonUsageStore newStore() =>
        JsonUsageStore(fs: storage.fs, filePath: storage.paths.usageEventsFile);

    JsonUsagePricingStore newPricingStore() => JsonUsagePricingStore(
      fs: storage.fs,
      filePath: storage.paths.usagePricingFile,
    );

    SessionUsageSyncService newSync() => SessionUsageSyncService(
      targets: TeamPilotUsageScanTargetProvider(
        storage: storage,
        loadSessions: loadSessionsFn,
        loadTeams: loadTeamsFn,
      ),
      store: newStore(),
      cursors: JsonUsageCursorStore(
        fs: storage.fs,
        filePath: storage.paths.usageCursorsFile,
      ),
      registry: registryForPlane,
    );

    UsageSyncHandle startSync() {
      final control = UsageSyncControl();
      final progress = StreamController<UsageSyncProgress>.broadcast(
        sync: true,
      );
      final service = newSync();
      final done = Future.microtask(
        () => service.syncAll(control: control, onProgress: progress.add),
      ).whenComplete(progress.close);
      return UsageSyncHandle(
        done: done,
        progress: progress.stream,
        cancel: control.cancel,
      );
    }

    return SessionUsageServices._(
      syncAll: () => newSync().syncAll(),
      startSync: startSync,
      loadEvents: () => newStore().readLatest(),
      loadPricing: () => newPricingStore().load(),
      savePricing: (rules) => newPricingStore().save(rules),
      loadSessions: loadSessionsFn,
      loadTeams: loadTeamsFn,
    );
  }
}
