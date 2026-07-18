import 'thread_turns.dart';
import 'turn_height_cache.dart';

/// Result of expanding an ideal mount window with short-lived keep-alive turns.
class KeepAliveMountResult {
  const KeepAliveMountResult({
    required this.range,
    this.nextExpiry,
  });

  final TurnVisibleRange range;

  /// Earliest keep-alive expiry still live, if any (for scheduling a tick).
  final DateTime? nextExpiry;
}

/// Expands [ideal] so recently departed mounts stay in the contiguous Column
/// briefly — Flutter stand-in for Claude Code leaving DOM nodes mounted.
///
/// Mutates [keepAliveUntil]:
/// - removes ids still inside [ideal] or expired / missing
/// - schedules [ttl] for [previousMountedIds] that just left [ideal]
/// - drops farthest keep-alives when extras exceed [maxExtraTurns]
///
/// Prefer [syncOffstageTurnCache] for history: contiguous expand caused remount
/// rebuild spikes (test60); offstage Element cache does not widen the Column.
KeepAliveMountResult expandVisibleRangeWithKeepAlive({
  required List<ThreadTurn> turns,
  required TurnHeightCache cache,
  required TurnVisibleRange ideal,
  required Set<String> previousMountedIds,
  required Map<String, DateTime> keepAliveUntil,
  required DateTime now,
  required Duration ttl,
  required int maxExtraTurns,
}) {
  if (turns.isEmpty || ideal.lastIndex < ideal.firstIndex) {
    keepAliveUntil.clear();
    return KeepAliveMountResult(range: ideal);
  }
  if (ttl <= Duration.zero || maxExtraTurns <= 0) {
    keepAliveUntil.clear();
    return KeepAliveMountResult(range: ideal);
  }

  final idealIds = <String>{};
  for (var i = ideal.firstIndex; i <= ideal.lastIndex; i++) {
    idealIds.add(turns[i].id);
  }

  // Still visible → no keep-alive entry.
  keepAliveUntil.removeWhere((id, _) => idealIds.contains(id));

  // Drop expired / unknown before scheduling — otherwise a still-mounted
  // keep-alive row would immediately renew its TTL via putIfAbsent.
  final expiredIds = <String>{};
  keepAliveUntil.removeWhere((id, until) {
    if (!until.isAfter(now)) {
      expiredIds.add(id);
      return true;
    }
    return !turns.any((t) => t.id == id);
  });

  // Just left the ideal window → start TTL (do not revive expired).
  for (final id in previousMountedIds) {
    if (idealIds.contains(id)) continue;
    if (expiredIds.contains(id)) continue;
    keepAliveUntil.putIfAbsent(id, () => now.add(ttl));
  }
  var first = ideal.firstIndex;
  var last = ideal.lastIndex;

  final keepIndices = <int>[];
  for (final id in keepAliveUntil.keys) {
    final idx = turns.indexWhere((t) => t.id == id);
    if (idx < 0) continue;
    keepIndices.add(idx);
  }
  keepIndices.sort();

  for (final idx in keepIndices) {
    first = first < idx ? first : idx;
    last = last > idx ? last : idx;
  }

  final idealCount = ideal.lastIndex - ideal.firstIndex + 1;
  var mounted = last - first + 1;
  final maxMounted = idealCount + maxExtraTurns;

  // Prefer keeping the ideal window; trim extras from the farther edge of scroll
  // focus (more keep-alive above → trim top first when over budget, etc.).
  while (mounted > maxMounted && first < ideal.firstIndex) {
    final id = turns[first].id;
    keepAliveUntil.remove(id);
    first++;
    mounted--;
  }
  while (mounted > maxMounted && last > ideal.lastIndex) {
    final id = turns[last].id;
    keepAliveUntil.remove(id);
    last--;
    mounted--;
  }

  DateTime? nextExpiry;
  for (final until in keepAliveUntil.values) {
    if (nextExpiry == null || until.isBefore(nextExpiry)) {
      nextExpiry = until;
    }
  }

  return KeepAliveMountResult(
    range: TurnVisibleRange(
      firstIndex: first,
      lastIndex: last,
      paddingTop: cache.offsetBefore(turns, first),
      paddingBottom:
          cache.totalExtent(turns) - cache.offsetBefore(turns, last + 1),
    ),
    nextExpiry: nextExpiry,
  );
}

/// Offstage Element-cache bookkeeping: keep [ideal] scroll window unchanged,
/// park departed turn ids in [keepAliveUntil] until TTL / [maxCached].
class OffstageCacheSyncResult {
  const OffstageCacheSyncResult({
    required this.offstageIds,
    required this.changed,
    this.nextExpiry,
  });

  final List<String> offstageIds;
  final bool changed;
  final DateTime? nextExpiry;
}

OffstageCacheSyncResult syncOffstageTurnCache({
  required List<ThreadTurn> turns,
  required Set<String> idealIds,
  required Set<String> previousIdealIds,
  required Map<String, DateTime> keepAliveUntil,
  required DateTime now,
  required Duration ttl,
  required int maxCached,
}) {
  if (ttl <= Duration.zero || maxCached <= 0) {
    final changed = keepAliveUntil.isNotEmpty;
    keepAliveUntil.clear();
    return OffstageCacheSyncResult(
      offstageIds: const [],
      changed: changed,
    );
  }

  final before = Map<String, DateTime>.from(keepAliveUntil);

  keepAliveUntil.removeWhere((id, _) => idealIds.contains(id));

  final expiredIds = <String>{};
  keepAliveUntil.removeWhere((id, until) {
    if (!until.isAfter(now)) {
      expiredIds.add(id);
      return true;
    }
    return !turns.any((t) => t.id == id);
  });

  for (final id in previousIdealIds) {
    if (idealIds.contains(id)) continue;
    if (expiredIds.contains(id)) continue;
    if (!turns.any((t) => t.id == id)) continue;
    keepAliveUntil.putIfAbsent(id, () => now.add(ttl));
  }

  // Trim oldest inserted first when over capacity (LinkedHashMap order).
  while (keepAliveUntil.length > maxCached) {
    keepAliveUntil.remove(keepAliveUntil.keys.first);
  }

  DateTime? nextExpiry;
  for (final until in keepAliveUntil.values) {
    if (nextExpiry == null || until.isBefore(nextExpiry)) {
      nextExpiry = until;
    }
  }

  final offstageIds = keepAliveUntil.keys.toList()
    ..sort((a, b) {
      final ia = turns.indexWhere((t) => t.id == a);
      final ib = turns.indexWhere((t) => t.id == b);
      return ia.compareTo(ib);
    });

  final changed = before.length != keepAliveUntil.length ||
      before.keys.any((k) => !keepAliveUntil.containsKey(k)) ||
      keepAliveUntil.keys.any((k) => !before.containsKey(k));

  return OffstageCacheSyncResult(
    offstageIds: offstageIds,
    changed: changed,
    nextExpiry: nextExpiry,
  );
}
