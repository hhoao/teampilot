import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

List<AiMessage> _messages(int count, {String prefix = 'm'}) => [
  for (var i = 0; i < count; i++)
    AiMessage(
      id: '$prefix-$i',
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
        home: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
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
    // Viewport is 120px / 40px ≈ 3 turns. Fail if overscan:5 leaked into
    // the reported range (that would be ~3 visible + 10 overscan ≈ 13).
    expect(ranges.last.lastIndex - ranges.last.firstIndex, lessThan(6));
    expect(ranges.last.firstIndex, inInclusiveRange(8, 12));
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

  testWidgets(
    'same index window with new turn ids notifies again',
    (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      final ranges = <TurnVisibleRange>[];

      Widget build(List<AiMessage> messages) => MaterialApp(
        home: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            height: 120,
            child: SingleChildScrollView(
              controller: controller,
              child: VirtualThreadViewport(
                messages: messages,
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

      await tester.pumpWidget(build(_messages(20)));
      await tester.pumpAndSettle();
      expect(ranges, isNotEmpty);
      final afterOpen = ranges.length;

      controller.jumpTo(0);
      await tester.pumpWidget(build(_messages(20, prefix: 'n')));
      await tester.pumpAndSettle();

      expect(ranges.length, greaterThan(afterOpen));
    },
  );

  testWidgets('unmounting turns notifies an empty visible range', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final ranges = <TurnVisibleRange>[];
    var mountTurns = true;

    Widget build() => MaterialApp(
      home: SizedBox(
        height: 120,
        child: SingleChildScrollView(
          controller: controller,
          child: VirtualThreadViewport(
            messages: _messages(8),
            scrollController: controller,
            estimateHeight: 40,
            mountTurns: mountTurns,
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
    );

    await tester.pumpWidget(build());
    await tester.pumpAndSettle();
    expect(ranges, isNotEmpty);
    expect(ranges.last.lastIndex, greaterThanOrEqualTo(0));
    final afterOpen = ranges.length;

    mountTurns = false;
    await tester.pumpWidget(build());
    await tester.pump();

    expect(ranges.length, greaterThan(afterOpen));
    expect(ranges.last.firstIndex, 0);
    expect(ranges.last.lastIndex, -1);
  });
}
