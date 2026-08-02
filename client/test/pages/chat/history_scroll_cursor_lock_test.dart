import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/pages/chat/history_scroll_cursor_lock.dart';
import 'package:teampilot/widgets/scroll_cursor_lock.dart';

/// Keeps the chat-history import path green after the rename to [ScrollCursorLock].
void main() {
  testWidgets('HistoryScrollCursorLock constructor builds ScrollCursorLock', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: HistoryScrollCursorLock(
          active: true,
          child: SizedBox.shrink(),
        ),
      ),
    );
    expect(find.byType(ScrollCursorLock), findsOneWidget);
    expect(
      tester.widget<ScrollCursorLock>(find.byType(ScrollCursorLock)).active,
      isTrue,
    );
  });
}
