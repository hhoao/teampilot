import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/widgets/diff/diff_view_controller.dart';

void main() {
  group('DiffViewController', () {
    test('starts empty', () {
      final c = DiffViewController();
      expect(c.changeCount, 0);
      expect(c.current, -1);
    });

    test('next/previous no-op when there are no changes', () {
      final c = DiffViewController();
      c.next();
      c.previous();
      expect(c.current, -1);
    });

    test('next advances and wraps around', () {
      final c = DiffViewController()..changeCount = 3;
      c.next();
      expect(c.current, 0);
      c.next();
      c.next();
      expect(c.current, 2);
      c.next();
      expect(c.current, 0); // wrapped
    });

    test('previous from start wraps to last', () {
      final c = DiffViewController()..changeCount = 3;
      c.previous();
      expect(c.current, 2);
    });

    test('shrinking changeCount clamps current', () {
      final c = DiffViewController()..changeCount = 5;
      c.next();
      c.next();
      c.next();
      expect(c.current, 2);
      c.changeCount = 2;
      expect(c.current, 1);
    });

    test('notifies listeners on navigation and count change', () {
      final c = DiffViewController();
      var notifications = 0;
      c.addListener(() => notifications++);
      c.changeCount = 2;
      c.next();
      expect(notifications, 2);
    });
  });
}
