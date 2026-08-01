import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/widgets/run/run_session_display_order.dart';

void main() {
  test('mergeDisplayOrderIds keeps preferred order and appends newcomers', () {
    final items = [
      ('c', 3),
      ('a', 1),
      ('d', 4),
      ('b', 2),
    ];
    final merged = mergeDisplayOrderIds(
      items: items,
      idOf: (e) => e.$1,
      orderIds: ['a', 'b', 'gone'],
    );
    expect(merged.map((e) => e.$1).toList(), ['a', 'b', 'c', 'd']);
  });
}
