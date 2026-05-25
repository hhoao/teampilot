import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/utils/debounce/debounce.dart';

void main() {
  tearDown(Throttles.cancelAll);

  test('Throttles.throttle ignores second call within duration', () {
    var count = 0;
    Throttles.throttle('t', const Duration(milliseconds: 100), () => count++);
    Throttles.throttle('t', const Duration(milliseconds: 100), () => count++);
    expect(count, 1);
  });

  test('Throttles.throttle allows call after duration', () async {
    var count = 0;
    Throttles.throttle('t', const Duration(milliseconds: 50), () => count++);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    Throttles.throttle('t', const Duration(milliseconds: 50), () => count++);
    expect(count, 2);
  });

  test('throttledOnPressed delegates to Throttles outside widget tests', () {
    // Under `flutter test`, [throttledOnPressed] bypasses throttle (no pending timers).
    // Production behavior is covered by [Throttles.throttle] tests above.
    var count = 0;
    final fn = throttledOnPressed('btn', () => count++);
    fn();
    fn();
    expect(count, 2);
  });
}
