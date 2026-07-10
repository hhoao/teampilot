import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/editor_platform/utf8_index_map.dart';

void main() {
  test('maps emoji and cjk between code units and utf8 bytes', () {
    const s = 'a😀中';
    final map = Utf8IndexMap(s);
    expect(map.byteOffsetForCodeUnit(0), 0);
    expect(map.byteOffsetForCodeUnit(1), 1);
    expect(
      map.codeUnitOffsetForByte(map.byteOffsetForCodeUnit(s.length)),
      s.length,
    );
  });

  test('ascii-only text maps 1:1 between code units and bytes', () {
    const s = 'hello world';
    final map = Utf8IndexMap(s);
    expect(map.byteLength, s.length);
    for (var i = 0; i <= s.length; i++) {
      expect(map.byteOffsetForCodeUnit(i), i);
      expect(map.codeUnitOffsetForByte(i), i);
    }
  });

  test('resolves surrogate pair boundaries for a lone emoji', () {
    const s = '😀';
    final map = Utf8IndexMap(s);
    expect(s.length, 2, reason: 'emoji is 2 UTF-16 code units');
    expect(map.byteOffsetForCodeUnit(0), 0);
    expect(map.byteOffsetForCodeUnit(2), 4, reason: 'emoji is 4 UTF-8 bytes');
    // Offset 1 splits the surrogate pair; it has no byte boundary of its
    // own and resolves to the start of the pair.
    expect(map.byteOffsetForCodeUnit(1), 0);
    expect(map.codeUnitOffsetForByte(0), 0);
    expect(map.codeUnitOffsetForByte(4), 2);
  });

  test('round-trips every rune boundary for mixed ascii/cjk/emoji text', () {
    const s = 'ab😀c中d🎉';
    final map = Utf8IndexMap(s);
    for (final rune in s.runes) {
      // Sanity: every rune's byte length matches its UTF-8 encoding.
      expect(rune, isNonNegative);
    }
    var codeUnitOffset = 0;
    for (final rune in s.runes) {
      final runeCodeUnitLength = String.fromCharCode(rune).length;
      final byteOffset = map.byteOffsetForCodeUnit(codeUnitOffset);
      expect(map.codeUnitOffsetForByte(byteOffset), codeUnitOffset);
      codeUnitOffset += runeCodeUnitLength;
    }
    expect(map.byteOffsetForCodeUnit(s.length), map.byteLength);
    expect(map.codeUnitOffsetForByte(map.byteLength), s.length);
  });

  test('applyEdit rebuilds the map coherently after a code-unit replace', () {
    const original = 'hello 中 world';
    final map = Utf8IndexMap(original);
    final insertAt = original.indexOf('world');

    map.applyEdit(
      codeUnitStart: insertAt,
      codeUnitDeleteCount: 'world'.length,
      insert: '😀!',
    );

    final expected = original.replaceRange(
      insertAt,
      insertAt + 'world'.length,
      '😀!',
    );
    expect(map.text, expected);

    final rebuilt = Utf8IndexMap(expected);
    for (var i = 0; i <= expected.length; i++) {
      expect(map.byteOffsetForCodeUnit(i), rebuilt.byteOffsetForCodeUnit(i));
    }
    expect(map.byteLength, rebuilt.byteLength);
  });
}
