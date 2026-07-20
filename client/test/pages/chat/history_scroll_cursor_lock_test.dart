import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/pages/chat/history_scroll_cursor_lock.dart';

void main() {
  testWidgets(
    'HistoryScrollCursorLock inactive defers to child click cursor',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: HistoryScrollCursorLock(
              active: false,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: SizedBox(width: 100, height: 100),
              ),
            ),
          ),
        ),
      );

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: tester.getCenter(find.byType(SizedBox)));
      addTearDown(gesture.removePointer);
      await tester.pump();

      expect(
        RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
        SystemMouseCursors.click,
      );
    },
  );

  testWidgets(
    'HistoryScrollCursorLock active forces basic over child click cursor',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: HistoryScrollCursorLock(
              active: true,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: SizedBox(width: 100, height: 100),
              ),
            ),
          ),
        ),
      );

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: tester.getCenter(find.byType(SizedBox)));
      addTearDown(gesture.removePointer);
      await tester.pump();

      expect(
        RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
        SystemMouseCursors.basic,
      );
    },
  );

  testWidgets(
    'HistoryScrollCursorLock active still delivers taps to child',
    (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HistoryScrollCursorLock(
              active: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => taps++,
                child: const SizedBox(width: 100, height: 100),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(GestureDetector));
      await tester.pump();
      expect(taps, 1);
    },
  );
}
