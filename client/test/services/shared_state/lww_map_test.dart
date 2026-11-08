import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/shared_state/hlc.dart';
import 'package:teampilot/services/shared_state/lww_map.dart';

void main() {
  const a1 = Hlc(wallMillis: 1, counter: 0, nodeId: 'a');
  const a2 = Hlc(wallMillis: 2, counter: 0, nodeId: 'a');
  const b1 = Hlc(wallMillis: 1, counter: 0, nodeId: 'b');

  test('different keys survive merge', () {
    final deviceA = const LwwMap<bool>().set('gridView', false, a1);
    final deviceB = const LwwMap<bool>().set('density', true, b1);

    final merged = deviceA.merge(deviceB);

    expect(merged['gridView'], isFalse);
    expect(merged['density'], isTrue);
  });

  test('same key keeps the newer stamp', () {
    final older = const LwwMap<bool>().set('gridView', false, a1);
    final newer = const LwwMap<bool>().set('gridView', true, a2);

    expect(older.merge(newer)['gridView'], isTrue);
    expect(newer.merge(older)['gridView'], isTrue);
  });

  test('json round-trips', () {
    final map = const LwwMap<String>()
        .set('sort', 'name', a1)
        .set('view', 'grid', a2);

    final decoded = LwwMap.fromJson<String>(
      map.toJson((value) => value),
      decode: (value) => value! as String,
    );

    expect(decoded['sort'], 'name');
    expect(decoded['view'], 'grid');
  });
}
