import 'package:flutter_test/flutter_test.dart';

import '../../../tool/performance_snapshot/summary_format.dart';

void main() {
  group('shortenHotPath', () {
    test('keeps path from BUILD onward', () {
      final path =
          'LAYOUT (root)${hotPathSeparator}LAYOUT${hotPathSeparator}BUILD${hotPathSeparator}RightToolsPanel${hotPathSeparator}FileTreePanel';
      expect(
        shortenHotPath(path),
        'BUILD${hotPathSeparator}RightToolsPanel${hotPathSeparator}FileTreePanel',
      );
    });

    test('truncates long layout-only paths', () {
      final path = List.generate(8, (i) => 'Node$i').join(hotPathSeparator);
      expect(shortenHotPath(path), startsWith('…$hotPathSeparator'));
      expect(shortenHotPath(path).split(hotPathSeparator).length, lessThanOrEqualTo(5));
    });
  });

  group('formatFrameList', () {
    test('formats and truncates frame numbers', () {
      expect(formatFrameList([445, 444]), '#444, #445');
      expect(formatFrameList([1, 2, 3, 4, 5]), '#1, #2, #3, #4 +1');
    });
  });
}
