import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/pages/chat/session_history_thread.dart';

List<AiMessage> _soloUserMessages(int count) {
  return List.generate(
    count,
    (i) => AiMessage(
      id: 'm$i',
      role: AiRole.user,
      parts: [AiTextPart(text: 'msg $i')],
    ),
  );
}

Widget _harness({
  required AiThreadRuntime runtime,
  bool hasOlder = false,
  bool isLoadingOlder = false,
  VoidCallback? onLoadOlder,
}) {
  return MaterialApp(
    theme: ThemeData(extensions: const [AiMessageTheme()]),
    home: Scaffold(
      body: SizedBox(
        width: 600,
        height: 400,
        child: SessionHistoryThread(
          runtime: runtime,
          hasOlder: hasOlder,
          isLoadingOlder: isLoadingOlder,
          onLoadOlder: onLoadOlder,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('SessionHistoryThread builds SelectionArea and VirtualThreadViewport', (
    tester,
  ) async {
    final store = ExternalStoreAiThreadRuntime()
      ..setMessages(_soloUserMessages(5));

    await tester.pumpWidget(_harness(runtime: store));
    await tester.pumpAndSettle();

    expect(find.byType(SelectionArea), findsOneWidget);
    expect(find.byType(Scrollable), findsWidgets);
    expect(find.byType(VirtualThreadViewport), findsOneWidget);
  });

  testWidgets(
    'SessionHistoryThread with hasOlder exposes viewport header and load-older',
    (tester) async {
      var loadOlderCalls = 0;
      final store = ExternalStoreAiThreadRuntime()
        ..setMessages(_soloUserMessages(40));

      await tester.pumpWidget(
        _harness(
          runtime: store,
          hasOlder: true,
          onLoadOlder: () => loadOlderCalls++,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(VirtualThreadViewport), findsOneWidget);

      // Break stick-to-end, then drag toward the top until load-older fires.
      final scrollable = find.byType(Scrollable).first;
      await tester.drag(scrollable, const Offset(0, 80));
      await tester.pumpAndSettle();

      for (var i = 0; i < 40 && loadOlderCalls == 0; i++) {
        await tester.drag(scrollable, const Offset(0, 400));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();

      expect(loadOlderCalls, greaterThan(0));
    },
  );

  testWidgets(
    'scroll-up rebuilds viewport with suppressMeasureScrollCorrection false',
    (tester) async {
      final store = ExternalStoreAiThreadRuntime()
        ..setMessages(_soloUserMessages(20));

      await tester.pumpWidget(_harness(runtime: store));
      await tester.pumpAndSettle();

      final before = tester.widget<VirtualThreadViewport>(
        find.byType(VirtualThreadViewport),
      );
      expect(before.suppressMeasureScrollCorrection, isTrue);

      await tester.drag(find.byType(Scrollable).first, const Offset(0, 120));
      await tester.pumpAndSettle();

      final after = tester.widget<VirtualThreadViewport>(
        find.byType(VirtualThreadViewport),
      );
      expect(after.suppressMeasureScrollCorrection, isFalse);
    },
  );
}
