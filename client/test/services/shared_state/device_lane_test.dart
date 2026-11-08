import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/shared_state/device_lane.dart';
import 'package:teampilot/services/shared_state/hlc.dart';

void main() {
  const a1 = Hlc(wallMillis: 1, counter: 0, nodeId: 'a');
  const a2 = Hlc(wallMillis: 2, counter: 0, nodeId: 'a');
  const b1 = Hlc(wallMillis: 1, counter: 0, nodeId: 'b');

  test('different devices merge without overwriting each other', () {
    final laneA = const DeviceLane<String>(
      items: ['w1', 'w2'],
      active: 'w1',
      stamp: a1,
    );
    final laneB = const DeviceLane<String>(
      items: ['w2', 'w3'],
      active: 'w2',
      stamp: b1,
    );

    final lanes = const DeviceLanes<String>()
        .put('a', laneA)
        .put('b', laneB)
        .merge(const DeviceLanes<String>());

    expect(lanes.itemsFor('a'), ['w1', 'w2']);
    expect(lanes.itemsFor('b'), ['w2', 'w3']);
    expect(lanes.activeFor('a'), 'w1');
    expect(lanes.activeFor('b'), 'w2');
  });

  test('union dedupes and orders by device id', () {
    final lanes = const DeviceLanes<String>()
        .put('b', const DeviceLane<String>(items: ['w2', 'w3'], stamp: b1))
        .put('a', const DeviceLane<String>(items: ['w1', 'w2'], stamp: a1));

    expect(lanes.unionItems, ['w1', 'w2', 'w3']);
  });

  test('same device keeps the newer lane', () {
    final older = const DeviceLanes<String>().put(
      'a',
      const DeviceLane<String>(items: ['w1'], stamp: a1),
    );
    final newer = const DeviceLanes<String>().put(
      'a',
      const DeviceLane<String>(items: ['w2'], stamp: a2),
    );

    expect(older.merge(newer).itemsFor('a'), ['w2']);
    expect(newer.merge(older).itemsFor('a'), ['w2']);
  });

  test('json round-trips', () {
    final lanes = const DeviceLanes<String>()
        .put(
          'a',
          const DeviceLane<String>(
            items: ['w1', 'w2'],
            active: 'w2',
            stamp: a1,
          ),
        )
        .put('b', const DeviceLane<String>(items: ['w3'], stamp: b1));

    final decoded = DeviceLanes.fromJson<String>(
      lanes.toJson((value) => value),
      decode: (value) => value! as String,
    );

    expect(decoded.itemsFor('a'), ['w1', 'w2']);
    expect(decoded.activeFor('a'), 'w2');
    expect(decoded.itemsFor('b'), ['w3']);
  });

  test('unreadable items are skipped without dropping the lane', () {
    final lane = DeviceLane.fromJson<String>(
      {
        'items': ['w1', 42, 'w2'],
        'active': 'w2',
        't': a1.toJson(),
      },
      decode: (value) {
        if (value is! String) throw const FormatException('not a string');
        return value;
      },
    );

    expect(lane?.items, ['w1', 'w2']);
    expect(lane?.stamp.toWire(), a1.toWire());
  });
}
