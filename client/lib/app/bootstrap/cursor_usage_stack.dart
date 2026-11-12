import '../../models/cursor_usage_account.dart';
import '../../models/cursor_usage_report.dart';
import '../../services/cli/cursor/provider/cursor_provider_settings_resolver.dart';
import '../../services/cli/cursor/provider/cursor_usage_auth_resolver.dart';
import '../../services/cursor_usage/cursor_account_registry.dart';
import '../../services/cursor_usage/cursor_usage_api_client.dart';
import '../../services/cursor_usage/cursor_usage_cache_store.dart';
import '../../services/cursor_usage/cursor_usage_coordinator.dart';
import '../../services/storage/home_storage.dart';
import '../../utils/logging/logger.dart';

/// The Cursor usage objects bound to one home storage plane.
///
/// `CursorUsageCacheStore` pairs a filesystem with paths resolved from the same
/// plane, so a plane swap has to rebuild the whole group, not just the paths.
class CursorUsageStack {
  CursorUsageStack({
    required HomeStorage storage,
    required CursorUsageApiClient api,
  }) : registry = CursorAccountRegistry(
         fs: storage.fs,
         accountsPath: storage.paths.cursorUsageAccountsFile,
         resolveAuths: () => CursorUsageAuthResolver(
           fs: storage.fs,
           basePath: storage.paths.basePath,
           home: storage.home,
           // Expired tokens are included so the usage page can show the account
           // as "expired, sign in again"; credentialFor filters them for sync.
         ).resolveAll(includeExpired: true),
         providerNameFor: (providerId) => CursorProviderSettingsResolver(
           basePath: storage.paths.basePath,
           storage: storage,
         ).findById(providerId).then((provider) => provider?.name),
       ),
       cacheStore = CursorUsageCacheStore(
         fs: storage.fs,
         pathFor: storage.paths.cursorUsageCacheFile,
       ) {
    coordinator = CursorUsageCoordinator(
      registry: registry,
      cacheStore: cacheStore,
      api: api,
    );
  }

  final CursorAccountRegistry registry;
  final CursorUsageCacheStore cacheStore;
  late final CursorUsageCoordinator coordinator;
}

/// Fills each enabled account's cache so the session usage dashboard has
/// account rows even if the Cursor page is never opened. Best effort.
Future<void> warmCursorUsage({
  required Future<List<CursorUsageAccount>> Function() accounts,
  required Future<CursorUsageReport> Function(String accountId) load,
}) async {
  final List<CursorUsageAccount> rows;
  try {
    rows = await accounts();
  } on Object {
    return;
  }
  for (final row in rows) {
    // Disabled rows are out by choice; expired rows have no live token, so a
    // warm load would only log a warning per boot.
    if (!row.enabled || row.isExpired(DateTime.now().millisecondsSinceEpoch)) {
      continue;
    }
    try {
      await load(row.accountId);
    } on Object catch (error) {
      AppLogger.instance.w(
        'cursor usage warm failed for ${row.accountId}: $error',
      );
    }
  }
}
