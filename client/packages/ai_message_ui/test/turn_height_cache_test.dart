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
    // viewport 0..250 → turns 0,1,2 visible; overscan 1 → 0..3
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
    // visible ~3..5, overscan → 2..6
    expect(range.firstIndex, 2);
    expect(range.lastIndex, 6);
    expect(range.paddingTop, 200); // turns 0..1
    expect(range.paddingBottom, 300); // turns 7..9
  });

  test('invalidate drops measured height', () {
    final cache = TurnHeightCache(estimate: 200);
    cache.setMeasured('a', 50);
    cache.invalidate('a');
    expect(cache.heightOf('a'), 200);
  });
}
