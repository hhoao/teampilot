import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/shared_state/hlc.dart';
import 'package:teampilot/services/shared_state/or_set.dart';

void main() {
  const aTag = Hlc(wallMillis: 1, counter: 0, nodeId: 'a');
  const bTag = Hlc(wallMillis: 1, counter: 0, nodeId: 'b');
  const aTag2 = Hlc(wallMillis: 2, counter: 0, nodeId: 'a');

  test('add makes an element present', () {
    final set = const OrSet().add('ws1', aTag);

    expect(set.contains('ws1'), isTrue);
    expect(set.values, {'ws1'});
    expect(set.contains('ws2'), isFalse);
  });

  test('remove of an observed add makes it absent', () {
    final set = const OrSet().add('ws1', aTag).remove('ws1');

    expect(set.contains('ws1'), isFalse);
    expect(set.values, isEmpty);
  });

  test('remove then re-add is present again', () {
    final set = const OrSet().add('ws1', aTag).remove('ws1').add('ws1', aTag2);

    expect(set.contains('ws1'), isTrue);
  });

  test('a concurrent add survives a remove that did not observe it', () {
    final deviceA = const OrSet().add('ws1', aTag);
    final deviceB = const OrSet().add('ws1', bTag);

    final removedOnlyA = deviceA.remove('ws1');
    final merged = removedOnlyA.merge(deviceB);

    expect(merged.contains('ws1'), isTrue);
  });

  test('remove without an observed add is a no-op', () {
    final removed = const OrSet().remove('ws1');

    expect(removed.contains('ws1'), isFalse);
    expect(removed.values, isEmpty);
  });

  test('merge is commutative and idempotent', () {
    final a = const OrSet().add('ws1', aTag).add('ws2', aTag);
    final b = const OrSet().add('ws1', bTag).add('ws3', bTag);

    final ab = a.merge(b);
    final ba = b.merge(a);

    expect(ab.values, ba.values);
    expect(ab.merge(b).values, ab.values);
    expect(ab.merge(ab).values, ab.values);
  });

  test('json round-trips', () {
    final set = const OrSet().add('ws1', aTag).add('ws2', bTag);

    final decoded = OrSet.fromJson(set.toJson());

    expect(decoded.values, set.values);
    expect(decoded.contains('ws1'), isTrue);
    expect(decoded.contains('ws2'), isTrue);
  });
}
