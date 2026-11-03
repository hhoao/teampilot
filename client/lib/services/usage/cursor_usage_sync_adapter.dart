import '../../models/cursor_usage_account.dart';
import '../../models/cursor_usage_range.dart';
import '../../models/session_usage_dashboard.dart';
import '../cursor_usage/cursor_usage_coordinator.dart';

/// Bridges the usage page's range onto the Cursor fetch range.
///
/// The page's "all" means every row available, not one billing cycle, so it
/// maps to the billing-cycle preset and is fetched in [CursorUsageSyncMode.manual]
/// — that mode expands the gap search to the history anchor. Every other range
/// maps to the matching preset or a custom window in
/// [CursorUsageSyncMode.auto].
final class CursorUsageSyncAdapter {
  CursorUsageSyncAdapter({
    required Future<List<CursorUsageAccount>> Function() listAccounts,
    required Future<void> Function(
      String accountId,
      CursorUsageRange range,
      CursorUsageSyncMode mode,
    )
    loadAccount,
    DateTime Function()? now,
  }) : _listAccounts = listAccounts,
       _loadAccount = loadAccount,
       _now = now ?? DateTime.now;

  final Future<List<CursorUsageAccount>> Function() _listAccounts;
  final Future<void> Function(
    String accountId,
    CursorUsageRange range,
    CursorUsageSyncMode mode,
  )
  _loadAccount;
  final DateTime Function() _now;

  /// Fetches every enabled account for [range]. A failing account must not
  /// block the others, so failures are swallowed per account; the page shows
  /// what the caches already hold.
  Future<void> syncFor(
    UsageRange range,
    int? startMs,
    int? endMs, {
    bool full = false,
  }) async {
    final cursorRange = rangeFor(range, startMs: startMs, endMs: endMs);
    final mode = full
        ? CursorUsageSyncMode.full
        : range == UsageRange.all
        ? CursorUsageSyncMode.manual
        : CursorUsageSyncMode.auto;
    for (final account in await _listAccounts()) {
      if (!account.enabled) continue;
      try {
        await _loadAccount(account.accountId, cursorRange, mode);
      } on Object {
        // One account failing must not block the others.
      }
    }
  }

  /// Maps the usage page range onto the Cursor fetch range.
  CursorUsageRange rangeFor(
    UsageRange range, {
    int? startMs,
    int? endMs,
  }) {
    final now = _now();
    final nowMs = now.millisecondsSinceEpoch;
    int daysAgo(int days) => DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: days - 1)).millisecondsSinceEpoch;
    return switch (range) {
      UsageRange.today => const CursorUsagePresetRange(CursorUsagePreset.today),
      UsageRange.last24Hours => CursorUsageCustomRange(
        startMs: nowMs - const Duration(days: 1).inMilliseconds,
        endMs: nowMs,
      ),
      UsageRange.sevenDays => const CursorUsagePresetRange(
        CursorUsagePreset.sevenDays,
      ),
      UsageRange.fourteenDays => CursorUsageCustomRange(
        startMs: daysAgo(14),
        endMs: nowMs,
      ),
      UsageRange.thirtyDays => const CursorUsagePresetRange(
        CursorUsagePreset.thirtyDays,
      ),
      UsageRange.all => const CursorUsagePresetRange(
        CursorUsagePreset.billingCycle,
      ),
      UsageRange.custom => CursorUsageCustomRange(
        startMs: startMs ?? daysAgo(30),
        endMs: endMs ?? nowMs,
      ),
    };
  }
}
