import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/utils/debounce/debounce.dart';

/// Clears pending debounce/throttle timers so widget tests do not fail with
/// "A Timer is still pending even after the widget tree was disposed".
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  tearDown(() {
    Throttles.cancelAll();
    Debounces.cancelAll();
  });
  await testMain();
}
