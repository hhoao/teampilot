import 'package:ai_message_ui/src/thread_turns.dart';
import 'package:ai_message_ui/src/turn_height_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('estimate used until measured', () {
    final cache = TurnHeightCache(estimate: 200);
    final turns = [
      const ThreadTurn(id: 'a', messageIds: ['a']),
      const ThreadTurn(id: 'b', messageIds: ['b']),
    ];
    expect(cache.heightOf('a'), 200);
    cache.setMeasured('a', 120);
    expect(cache.heightOf('a'), 120);
    expect(cache.totalExtent(turns), 320);
  });

  test('visibleRange covers pixels with overscan', () {
    final cache = TurnHeightCache(estimate: 100);
    final turns = List.generate(
      10,
      (i) => ThreadTurn(id: 't$i', messageIds: ['t$i']),
    );
    final range = cache.visibleRange(
      turns: turns,
      scrollPixels: 0,
      viewportHeight: 250,
      overscan: 1,
    );
    expect(range.firstIndex, 0);
    expect(range.lastIndex, 3);
    expect(range.paddingTop, 0);
  });

  test('visibleRange mid-list pads top/bottom', () {
    final cache = TurnHeightCache(estimate: 100);
    for (var i = 0; i < 10; i++) {
      cache.setMeasured('t$i', 100);
    }
    final turns = List.generate(
      10,
      (i) => ThreadTurn(id: 't$i', messageIds: ['t$i']),
    );
    final range = cache.visibleRange(
      turns: turns,
      scrollPixels: 350,
      viewportHeight: 200,
      overscan: 1,
    );
    expect(range.firstIndex, 2);
    expect(range.lastIndex, 6);
    expect(range.paddingTop, 200);
    expect(range.paddingBottom, 300);
  });

  test('invalidate drops measured height', () {
    final cache = TurnHeightCache(estimate: 200);
    cache.setMeasured('a', 50);
    cache.invalidate('a');
    expect(cache.heightOf('a'), 200);
  });

  test('clampUnmeasuredMounts shrinks estimate-heavy window at end', () {
    final cache = TurnHeightCache(estimate: 100);
    final turns = List.generate(
      20,
      (i) => ThreadTurn(id: 't$i', messageIds: ['t$i']),
    );
    final wide = cache.visibleRange(
      turns: turns,
      scrollPixels: 1500,
      viewportHeight: 400,
      overscan: 3,
    );
    expect(wide.lastIndex - wide.firstIndex + 1, greaterThan(3));

    final clamped = cache.clampUnmeasuredMounts(
      turns: turns,
      range: wide,
      maxUnmeasured: 3,
      preferEnd: true,
    );
    expect(clamped.lastIndex, wide.lastIndex);
    var unmeasured = 0;
    for (var i = clamped.firstIndex; i <= clamped.lastIndex; i++) {
      if (!cache.isMeasured(turns[i].id)) unmeasured++;
    }
    expect(unmeasured, lessThanOrEqualTo(3));
  });

  test('clampUnmeasuredMounts keeps measured neighbors when admitting cold rows',
      () {
    final cache = TurnHeightCache(estimate: 100);
    final turns = List.generate(
      12,
      (i) => ThreadTurn(id: 't$i', messageIds: ['t$i']),
    );
    for (var i = 0; i < 4; i++) {
      cache.setMeasured('t$i', 100);
    }
    final range = TurnVisibleRange(
      firstIndex: 0,
      lastIndex: 11,
      paddingTop: 0,
      paddingBottom: 0,
    );
    final clamped = cache.clampUnmeasuredMounts(
      turns: turns,
      range: range,
      maxUnmeasured: 2,
      preferEnd: false,
    );
    expect(clamped.firstIndex, 0);
    expect(clamped.lastIndex, 5); // 0..3 measured + 4,5 unmeasured
  });
}
