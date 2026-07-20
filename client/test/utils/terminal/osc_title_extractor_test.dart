import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/utils/terminal/osc_title_extractor.dart';

void main() {
  group('OscTitleExtractor', () {
    test('extracts last OSC title from BEL-terminated PTY data', () {
      expect(
        OscTitleExtractor.extractLast('\x1b]0;First\x07noise\x1b]2;Second\x07'),
        'Second',
      );
    });

    test('extracts all OSC titles including ST-terminated titles', () {
      expect(
        OscTitleExtractor.extractAll(
          '\x1b]0;First\x1b\\noise\x1b]2;Second\x07',
        ),
        ['First', 'Second'],
      );
    });

    test('accepts OSC cmds 0, 1, and 2', () {
      expect(OscTitleExtractor.extractLast('\x1b]0;Zero\x07'), 'Zero');
      expect(OscTitleExtractor.extractLast('\x1b]1;One\x07'), 'One');
      expect(OscTitleExtractor.extractLast('\x1b]2;Two\x07'), 'Two');
    });

    test('ignores incomplete OSC titles until a terminator arrives', () {
      expect(OscTitleExtractor.extractAll('\x1b]0;Incomplete title'), isEmpty);
      expect(OscTitleExtractor.extractLast('\x1b]0;Incomplete title'), isNull);
    });

    test('recovers when abandoned incomplete OSC is followed by a fresh title', () {
      const data = '\x1b]0;abandoned\x1b]0;Fresh title\x07';
      expect(OscTitleExtractor.extractLast(data), 'Fresh title');
      expect(OscTitleExtractor.extractAll(data), ['Fresh title']);
    });

    test('caps oversized OSC titles', () {
      final title =
          '${'a' * OscTitleExtractor.maxOscTitleChars}${'b' * 10000}';
      final data = 'before\x1b]0;$title\x07after';
      final extracted = OscTitleExtractor.extractLast(data);
      expect(extracted, hasLength(OscTitleExtractor.maxOscTitleChars));
      expect(
        extracted!.startsWith('a' * (OscTitleExtractor.maxOscTitleChars ~/ 2)),
        isTrue,
      );
      expect(
        extracted.endsWith(
          'b' * (OscTitleExtractor.maxOscTitleChars -
              OscTitleExtractor.maxOscTitleChars ~/ 2),
        ),
        isTrue,
      );
    });

    test('stateful push completes titles split across chunks', () {
      final extractor = OscTitleExtractor();
      expect(extractor.push('\x1b]0;Hello'), isEmpty);
      expect(extractor.push(' world\x07'), ['Hello world']);
    });

    test('stateful push completes ST terminator split across chunks', () {
      final extractor = OscTitleExtractor();
      expect(extractor.push('\x1b]2;Split'), isEmpty);
      expect(extractor.push('\x1b'), isEmpty);
      expect(extractor.push(r'\'), ['Split']);
    });
  });
}
