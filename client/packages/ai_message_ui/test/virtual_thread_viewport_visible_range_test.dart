import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

List<AiMessage> _messages(int count) => [
  for (var i = 0; i < count; i++)
    AiMessage(
      id: 'm-$i',
      role: AiRole.user,
      parts: [AiTextPart(text: 'msg-$i')],
    ),
];

void main() {
  testWidgets('scroll reports a new viewport turn range', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final ranges = <TurnVisibleRange>[];

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          height: 120,
          child: SingleChildScrollView(
            controller: controller,
            child: VirtualThreadViewport(
              messages: _messages(20),
              scrollController: controller,
              estimateHeight: 40,
              mountTurns: true,
              retainMountedTurns: true,
              fillDataWindow: true,
              overscan: 5,
              onVisibleRange: ranges.add,
              messageBuilder: (context, message) => SizedBox(
                height: 40,
                child: Text(message.id),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(ranges, isNotEmpty);
    final afterOpen = ranges.length;
    final firstOpen = ranges.last.firstIndex;

    controller.jumpTo(400);
    await tester.pumpAndSettle();

    expect(ranges.length, greaterThan(afterOpen));
    expect(ranges.last.firstIndex, greaterThan(firstOpen));
    expect(ranges.last.lastIndex - ranges.last.firstIndex, lessThan(19));
  });

  testWidgets('unchanged turn range does not spam callbacks', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final ranges = <TurnVisibleRange>[];

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          height: 400,
          child: SingleChildScrollView(
            controller: controller,
            child: VirtualThreadViewport(
              messages: _messages(8),
              scrollController: controller,
              estimateHeight: 40,
              mountTurns: true,
              retainMountedTurns: true,
              fillDataWindow: true,
              overscan: 0,
              onVisibleRange: ranges.add,
              messageBuilder: (context, message) => SizedBox(
                height: 40,
                child: Text(message.id),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final afterOpen = ranges.length;

    controller.jumpTo(4);
    await tester.pump();
    controller.jumpTo(8);
    await tester.pump();

    expect(ranges.length, afterOpen);
  });
}
