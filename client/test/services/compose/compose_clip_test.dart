// client/test/services/compose/compose_clip_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/compose/compose_clip.dart';

void main() {
  group('ComposeClip', () {
    test('starts empty and not collapsed', () {
      final clip = ComposeClip();
      expect(clip.collapsed, isFalse);
      expect(clip.text, isNull);
      expect(clip.lineCount, 1);
    });

    test('setPasted collapses with the block and line count', () {
      final clip = ComposeClip();
      clip.setPasted('a\nb\nc');
      expect(clip.collapsed, isTrue);
      expect(clip.text, 'a\nb\nc');
      expect(clip.lineCount, 3);
    });

    test('composeMessage joins block and follow-up with a blank line', () {
      final clip = ComposeClip();
      clip.setPasted('block');
      expect(clip.composeMessage(''), 'block');
      expect(clip.composeMessage('why?'), 'block\n\nwhy?');
    });

    test('composeMessage with empty clip returns follow-up only', () {
      final clip = ComposeClip();
      expect(clip.composeMessage('why?'), 'why?');
    });

    test('setExpanded updates text but stays collapsed', () {
      final clip = ComposeClip();
      clip.setPasted('a\nb');
      clip.setExpanded('a\nb\nc\nd');
      expect(clip.collapsed, isTrue);
      expect(clip.lineCount, 4);
    });

    test('clear resets to empty', () {
      final clip = ComposeClip();
      clip.setPasted('text');
      clip.clear();
      expect(clip.collapsed, isFalse);
      expect(clip.text, isNull);
    });

    test('countLines counts newlines + 1', () {
      expect(ComposeClip.countLines(''), 1);
      expect(ComposeClip.countLines('a'), 1);
      expect(ComposeClip.countLines('a\nb\nc'), 3);
      expect(ComposeClip.countLines('a\nb\n'), 3);
    });
  });
}
