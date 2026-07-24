import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/workbench/workbench_tab.dart';
import 'package:teampilot/services/workbench/workbench_strip_nav.dart';

void main() {
  final s1 = WorkbenchTabId.session('s1');
  final file = WorkbenchTabId.file('/tmp/a.dart');
  final diff = WorkbenchTabId.diffChanges('/tmp/a.dart');
  final shell = WorkbenchTabId.shell('e1');
  final order = [s1, file, diff, shell];

  group('workbenchTabAt', () {
    test('returns 1-based ordinal within strip order', () {
      expect(workbenchTabAt(order, 1), s1);
      expect(workbenchTabAt(order, 2), file);
      expect(workbenchTabAt(order, 4), shell);
    });

    test('returns null when ordinal out of range or empty', () {
      expect(workbenchTabAt(order, 0), isNull);
      expect(workbenchTabAt(order, 5), isNull);
      expect(workbenchTabAt(order, 11), isNull);
      expect(workbenchTabAt(const [], 1), isNull);
    });

    test('Alt+0 maps to ordinal 10', () {
      final ten = [
        for (var i = 1; i <= 10; i++) WorkbenchTabId.session('s$i'),
      ];
      expect(workbenchTabAt(ten, 10), WorkbenchTabId.session('s10'));
    });
  });

  group('workbenchNextTab / workbenchPrevTab', () {
    test('wraps forward and backward across mixed kinds', () {
      expect(workbenchNextTab(order, s1), file);
      expect(workbenchNextTab(order, shell), s1);
      expect(workbenchPrevTab(order, s1), shell);
      expect(workbenchPrevTab(order, file), s1);
    });

    test('empty strip is a no-op target', () {
      expect(workbenchNextTab(const [], s1), isNull);
      expect(workbenchPrevTab(const [], s1), isNull);
    });

    test('unknown active falls back to first / last', () {
      final orphan = WorkbenchTabId.session('gone');
      expect(workbenchNextTab(order, orphan), s1);
      expect(workbenchPrevTab(order, orphan), shell);
      expect(workbenchNextTab(order, null), s1);
      expect(workbenchPrevTab(order, null), shell);
    });
  });
}
