import '../../cubits/notification_cubit.dart';
import '../../cubits/progress_activity_cubit.dart';
import '../../cubits/session_usage_cubit.dart';
import '../../models/cursor_usage_range.dart';
import '../../repositories/launch_profile_repository.dart';
import '../../repositories/session_repository.dart';
import '../../services/cli/registry/cli_tool_registry.dart';
import '../../services/cursor_usage/cursor_usage_api_client.dart';
import '../../services/cursor_usage/cursor_usage_event_source.dart';
import '../../services/notification/notification_recorder.dart';
import '../../services/storage/home_storage.dart';
import '../../services/usage/cursor_usage_sync_adapter.dart';
import '../../utils/retryable_memo.dart';
import '../session_usage_services.dart';
import 'cursor_usage_stack.dart';

/// Session usage aggregation plus the notification and progress-activity
/// cubits that the shell boots alongside it.
typedef SessionUsageWiring = ({
  CursorUsageApiClient cursorUsageApiClient,
  SessionUsageCubit sessionUsageCubit,
  Future<void> Function() warmStartupCaches,
  NotificationCubit notificationCubit,
  Future<void> Function() notificationBootstrap,
  ProgressActivityCubit progressActivityCubit,
});

/// Builds the session usage and notification objects bound to one home plane.
///
/// The Cursor stack inside is rebuilt on every home-plane change, so the
/// returned `warmStartupCaches` keeps tracking the active plane.
SessionUsageWiring wireSessionUsage({
  required HomeStorage storage,
  required CliToolRegistry registry,
  required SessionRepository sessions,
  required LaunchProfileRepository teams,
}) {
  final cursorUsageApiClient = CursorUsageApiClient();
  // The Cursor stack resolves paths and the filesystem from the active home
  // plane, so it is rebuilt whenever that plane changes instead of pinning
  // the first one for the whole app lifetime.
  var cursorStackGeneration = -1;
  CursorUsageStack? cachedCursorStack;
  CursorUsageStack cursorStack() {
    if (cachedCursorStack == null ||
        cursorStackGeneration != storage.generation) {
      cursorStackGeneration = storage.generation;
      cachedCursorStack = CursorUsageStack(
        storage: storage,
        api: cursorUsageApiClient,
      );
    }
    return cachedCursorStack!;
  }

  final cursorAdapter = CursorUsageSyncAdapter(
    listAccounts: () => cursorStack().registry.list(),
    loadAccount: (accountId, range, mode) => cursorStack().coordinator.load(
      accountId: accountId,
      range: range,
      mode: mode,
    ),
  );

  final sessionUsageServices = SessionUsageServices.forStorage(
    storage: storage,
    registry: registry,
    sessions: sessions,
    teams: teams,
    loadCursorAccountUsage: () => CursorUsageEventSource(
      listAccounts: () => cursorStack().registry.list(),
      loadCache: (accountId) => cursorStack().cacheStore.load(accountId),
    ).loadEvents(),
    loadCursorAccounts: () => cursorStack().registry.list(),
    syncCursorUsage: (range, startMs, endMs, full) =>
        cursorAdapter.syncFor(range, startMs, endMs, full: full),
  );
  final sessionUsageCubit = SessionUsageCubit(
    loadEvents: sessionUsageServices.loadEvents,
    syncAll: sessionUsageServices.syncAll,
    startSync: sessionUsageServices.startSync,
    startFullSync: sessionUsageServices.startFullSync,
    loadPricing: sessionUsageServices.loadPricing,
    savePricing: sessionUsageServices.savePricing,
    loadUsageStats: sessionUsageServices.loadUsageStats,
    compactUsage: sessionUsageServices.compactUsage,
    loadSessions: sessionUsageServices.loadSessions,
    loadTeams: sessionUsageServices.loadTeams,
    loadCursorAccounts: sessionUsageServices.loadCursorAccounts,
    syncCursorUsage: sessionUsageServices.syncCursorUsage,
    storageChanges: storage.changes.map<void>((_) {}),
  );
  // Usage events are loaded on demand by the usage page. Loading them here
  // would pull the whole event store through the home plane before the
  // first frame — tens of MB over SSH, decrypted on the UI isolate.
  Future<void> warmStartupCaches() => warmCursorUsage(
    accounts: () => cursorStack().registry.list(),
    load: (accountId) => cursorStack().coordinator.load(
      accountId: accountId,
      range: const CursorUsagePresetRange(CursorUsagePreset.billingCycle),
    ),
  );

  final notificationCubit = NotificationCubit(storage: storage);
  // Lazy: the first read is home-plane I/O, so the unreachable splash must
  // not start it. Success is memoized; a transient failure is not, so the
  // next hot-recovery attempt retries instead of reusing a rejected future.
  final notificationBootstrap = retryableMemo(notificationCubit.load);
  NotificationRecorder.install(notificationCubit);
  final progressActivityCubit = ProgressActivityCubit(
    historyRecorder: notificationCubit,
  );

  return (
    cursorUsageApiClient: cursorUsageApiClient,
    sessionUsageCubit: sessionUsageCubit,
    warmStartupCaches: warmStartupCaches,
    notificationCubit: notificationCubit,
    notificationBootstrap: notificationBootstrap,
    progressActivityCubit: progressActivityCubit,
  );
}
