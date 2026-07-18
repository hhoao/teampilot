import 'package:ai_message_ui/src/thread_turns.dart';
import 'package:ai_message_ui/src/turn_height_cache.dart';
import 'package:ai_message_ui/src/turn_mount_keep_alive.dart';
import 'package:flutter_test/flutter_test.dart';

List<ThreadTurn> _turns(int n) => List.generate(
      n,
      (i) => ThreadTurn(id: 't$i', messageIds: ['t$i']),
    );

void main() {
  test('expandKeepAlive keeps recently departed turns in contiguous window', () {
    final cache = TurnHeightCache(estimate: 100);
    final turns = _turns(20);
    for (final t in turns) {
      cache.setMeasured(t.id, 100);
    }

    final ideal = TurnVisibleRange(
      firstIndex: 8,
      lastIndex: 11,
      paddingTop: 800,
      paddingBottom: 800,
    );

    final previousMounted = {'t5', 't6', 't7', 't8', 't9', 't10', 't11'};
    final now = DateTime.utc(2026, 7, 18, 12);
    final keepUntil = <String, DateTime>{
      't5': now.add(const Duration(seconds: 2)),
      't6': now.add(const Duration(seconds: 2)),
      't7': now.add(const Duration(seconds: 2)),
    };

    final expanded = expandVisibleRangeWithKeepAlive(
      turns: turns,
      cache: cache,
      ideal: ideal,
      previousMountedIds: previousMounted,
      keepAliveUntil: keepUntil,
      now: now,
      ttl: const Duration(seconds: 2),
      maxExtraTurns: 8,
    );

    expect(expanded.range.firstIndex, 5);
    expect(expanded.range.lastIndex, 11);
    expect(expanded.range.paddingTop, 500);
    expect(keepUntil.containsKey('t5'), isTrue);
    expect(keepUntil.containsKey('t8'), isFalse); // still in ideal
  });

  test('expandKeepAlive drops expired turns', () {
    final cache = TurnHeightCache(estimate: 100);
    final turns = _turns(20);
    for (final t in turns) {
      cache.setMeasured(t.id, 100);
    }

    final ideal = TurnVisibleRange(
      firstIndex: 8,
      lastIndex: 11,
      paddingTop: 800,
      paddingBottom: 800,
    );
    final now = DateTime.utc(2026, 7, 18, 12);
    final keepUntil = <String, DateTime>{
      't5': now.subtract(const Duration(milliseconds: 1)),
      't6': now.add(const Duration(seconds: 1)),
      't7': now.add(const Duration(seconds: 1)),
    };

    final expanded = expandVisibleRangeWithKeepAlive(
      turns: turns,
      cache: cache,
      ideal: ideal,
      previousMountedIds: {'t5', 't6', 't7', 't8'},
      keepAliveUntil: keepUntil,
      now: now,
      ttl: const Duration(seconds: 2),
      maxExtraTurns: 8,
    );

    expect(expanded.range.firstIndex, 6);
    expect(keepUntil.containsKey('t5'), isFalse);
  });

  test('expandKeepAlive does not renew TTL after expiry while still mounted', () {
    final cache = TurnHeightCache(estimate: 100);
    final turns = _turns(20);
    for (final t in turns) {
      cache.setMeasured(t.id, 100);
    }

    final ideal = TurnVisibleRange(
      firstIndex: 8,
      lastIndex: 11,
      paddingTop: 800,
      paddingBottom: 800,
    );
    final now = DateTime.utc(2026, 7, 18, 12);
    final keepUntil = <String, DateTime>{
      't5': now.subtract(const Duration(milliseconds: 1)),
      't6': now.subtract(const Duration(milliseconds: 1)),
      't7': now.subtract(const Duration(milliseconds: 1)),
    };

    final expanded = expandVisibleRangeWithKeepAlive(
      turns: turns,
      cache: cache,
      ideal: ideal,
      // Still physically mounted from prior keep-alive frame.
      previousMountedIds: {'t5', 't6', 't7', 't8', 't9', 't10', 't11'},
      keepAliveUntil: keepUntil,
      now: now,
      ttl: const Duration(seconds: 2),
      maxExtraTurns: 8,
    );

    expect(expanded.range.firstIndex, 8);
    expect(keepUntil, isEmpty);
  });

  test('syncOffstageTurnCache parks departed ids without expanding range', () {
    final turns = _turns(20);
    final now = DateTime.utc(2026, 7, 18, 12);
    final keepUntil = <String, DateTime>{};

    final result = syncOffstageTurnCache(
      turns: turns,
      idealIds: {'t8', 't9', 't10', 't11'},
      previousIdealIds: {'t0', 't1', 't2', 't3', 't8', 't9'},
      keepAliveUntil: keepUntil,
      now: now,
      ttl: const Duration(seconds: 2),
      maxCached: 8,
    );

    expect(result.offstageIds, containsAll(['t0', 't1', 't2', 't3']));
    expect(result.offstageIds, isNot(contains('t8')));
    expect(keepUntil['t0']!.isAfter(now), isTrue);
  });
}
