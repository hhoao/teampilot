import '../../models/cursor_usage_account.dart';
import '../../models/cursor_usage_report.dart';
import '../../models/session_usage.dart';
import '../../models/team_config.dart';

/// Synthetic session id for account-level Cursor rows.
const cursorAccountUsageSessionId = 'cursor-account-usage';

/// Turns the per-account caches into [SessionUsageEvent]s so the session usage
/// dashboard totals every Cursor account.
///
/// Uses the `days` aggregates rather than the raw 90-day `events` list: older
/// ranges still count, and `days` is derived from `events`, so the two can
/// never double count.
final class CursorUsageEventSource {
  CursorUsageEventSource({
    required Future<List<CursorUsageAccount>> Function() listAccounts,
    required Future<CursorUsageCache> Function(String accountId) loadCache,
  }) : _listAccounts = listAccounts,
       _loadCache = loadCache;

  final Future<List<CursorUsageAccount>> Function() _listAccounts;
  final Future<CursorUsageCache> Function(String accountId) _loadCache;

  Future<List<SessionUsageEvent>> loadEvents() async {
    final accounts = await _listAccounts();
    final out = <SessionUsageEvent>[];
    for (final account in accounts) {
      if (!account.enabled) continue;
      final cache = await _loadCache(account.accountId);
      for (final day in cache.days) {
        for (final entry in day.models.entries) {
          final totals = entry.value;
          if (totals.totalTokens == 0 && totals.totalCents == 0) continue;
          out.add(
            SessionUsageEvent(
              requestId:
                  'cursor-account:${account.accountId}:${day.dayMs}:${entry.key}',
              cli: CliTool.cursor,
              model: entry.key.trim().isEmpty ? 'cursor-auto' : entry.key,
              inputTokens: totals.inputTokens,
              outputTokens: totals.outputTokens,
              cacheReadTokens: totals.cacheReadTokens,
              cacheCreationTokens: totals.cacheWriteTokens,
              inputSemantics: UsageInputSemantics.fresh,
              timestampMs: day.dayMs,
              sessionId: cursorAccountUsageSessionId,
              accountId: account.accountId,
              costMicroUsd: (totals.totalCents * 10000).round(),
            ),
          );
        }
      }
    }
    return out;
  }
}
