import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';

void main() {
  // NOTE: two taps must each come from a *fresh* pointer. Reusing one
  // TestGesture for both downs trips a framework gesture-arena assertion
  // ('isOpen': is not true) unrelated to TpHover — it reproduces on a bare
  // GestureDetector too.
  testWidgets('TpHover onDoubleTap fires on double tap (desktop)', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    var single = 0;
    var dbl = 0;
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: TpHover(
                onTap: () => single++,
                onDoubleTap: () => dbl++,
                width: 120,
                height: 40,
                child: const Text('x'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('x'), kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('x'), kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 400));
      expect(dbl, 1);
      expect(single, 0); // two taps collapsed into the double tap
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('TpHover onDoubleTap fires on double tap (touch)', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    var single = 0;
    var dbl = 0;
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: TpHover(
                onTap: () => single++,
                onDoubleTap: () => dbl++,
                width: 120,
                height: 40,
                child: const Text('x'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('x'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('x'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(dbl, 1);
      expect(single, 0); // two taps collapsed into the double tap
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
