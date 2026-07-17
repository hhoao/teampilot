import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Finder _mountedMessageFinder() {
  return find.byWidgetPredicate(
    (w) =>
        w is Text &&
        (w.key as ValueKey<String>?)?.value.startsWith('msg-') == true,
  );
}

Set<String> _mountedMessageIds(WidgetTester tester) {
  return _mountedMessageFinder()
      .evaluate()
      .map((e) => ((e.widget as Text).key! as ValueKey<String>).value)
      .toSet();
}

List<AiMessage> _pairedMessages(int count) {
  return List.generate(
    count,
    (i) => AiMessage(
      id: 'm$i',
      role: i.isEven ? AiRole.user : AiRole.assistant,
      parts: [AiTextPart(text: 't$i')],
    ),
  );
}

/// One user message per turn so turn height == message height.
List<AiMessage> _soloUserMessages(int count) {
  return List.generate(
    count,
    (i) => AiMessage(
      id: 'm$i',
      role: AiRole.user,
      parts: [AiTextPart(text: 't$i')],
    ),
  );
}

Widget _harness({
  required List<AiMessage> messages,
  required ScrollController controller,
  int overscan = 2,
  double estimateHeight = 100,
  Widget? header,
  void Function(double deltaPixels)? onMeasureScrollCorrection,
  Widget Function(BuildContext context, AiMessage message)? messageBuilder,
}) {
  return MaterialApp(
    home: SizedBox(
      height: 400,
      child: SingleChildScrollView(
        controller: controller,
        child: VirtualThreadViewport(
          messages: messages,
          scrollController: controller,
          overscan: overscan,
          estimateHeight: estimateHeight,
          header: header,
          onMeasureScrollCorrection: onMeasureScrollCorrection,
          messageBuilder: messageBuilder ??
              (_, m) => SizedBox(
                    height: 100,
                    width: double.infinity,
                    child: Text(m.id, key: ValueKey('msg-${m.id}')),
                  ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('mounts at most viewport+overscan turns', (tester) async {
    final controller = ScrollController();
    final messages = _pairedMessages(40);
    await tester.pumpWidget(
      _harness(messages: messages, controller: controller),
    );
    await tester.pumpAndSettle();

    // 40 messages → ~20 turns if paired; with height 100 and viewport 400
    // visible turns ~4 + overscan 2*2 → mount cap well under 20.
    final mounted = _mountedMessageFinder();
    expect(mounted.evaluate().length, lessThan(messages.length));
    expect(mounted.evaluate().length, lessThanOrEqualTo(20)); // generous cap
  });

  testWidgets('jumpTo mid moves mounted message window', (tester) async {
    final controller = ScrollController();
    final messages = _pairedMessages(40);
    await tester.pumpWidget(
      _harness(messages: messages, controller: controller),
    );
    await tester.pumpAndSettle();

    final before = _mountedMessageIds(tester);
    expect(before, isNotEmpty);

    final mid = controller.position.maxScrollExtent / 2;
    controller.jumpTo(mid);
    await tester.pumpAndSettle();

    final after = _mountedMessageIds(tester);
    expect(after, isNotEmpty);
    expect(after, isNot(equals(before)));
  });

  testWidgets('tall header shifts which messages mount at same scroll', (
    tester,
  ) async {
    final controller = ScrollController();
    final messages = _soloUserMessages(40);
    const headerHeight = 500.0;

    await tester.pumpWidget(
      _harness(
        messages: messages,
        controller: controller,
        overscan: 1,
        header: const SizedBox(
          height: headerHeight,
          width: double.infinity,
          child: Text('HEADER'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Document offset just past the header → turn-space scroll ≈ 0.
    // Without subtracting header height, visibleRange treats 500 as mid-list.
    controller.jumpTo(headerHeight);
    await tester.pumpAndSettle();

    final mounted = _mountedMessageIds(tester);
    expect(mounted, contains('msg-m0'));
    expect(mounted, isNot(contains('msg-m10')));
  });

  testWidgets('expand fully above viewport requests scroll correction', (
    tester,
  ) async {
    final controller = ScrollController();
    final messages = _soloUserMessages(20);
    final heights = <String, double>{
      for (final m in messages) m.id: 100,
    };
    final corrections = <double>[];

    late void Function(void Function()) setHarnessState;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            setHarnessState = setState;
            return SizedBox(
              height: 400,
              child: SingleChildScrollView(
                controller: controller,
                child: VirtualThreadViewport(
                  messages: messages,
                  scrollController: controller,
                  // Keep turn0 mounted in overscan while viewport top is past it.
                  overscan: 3,
                  estimateHeight: 100,
                  onMeasureScrollCorrection: corrections.add,
                  messageBuilder: (_, m) => SizedBox(
                    height: heights[m.id]!,
                    width: double.infinity,
                    child: Text(m.id, key: ValueKey('msg-${m.id}')),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Viewport top at turn-space 250 → turn0 (0–100) fully above.
    controller.jumpTo(250);
    await tester.pumpAndSettle();
    corrections.clear();

    setHarnessState(() {
      heights['m0'] = 200;
    });
    await tester.pumpAndSettle();

    expect(corrections, isNotEmpty);
    expect(corrections.reduce((a, b) => a + b), closeTo(100, 1));
  });

  testWidgets('expand straddling viewport top does not correct', (
    tester,
  ) async {
    final controller = ScrollController();
    final messages = _soloUserMessages(20);
    final heights = <String, double>{
      for (final m in messages) m.id: 100,
    };
    final corrections = <double>[];

    late void Function(void Function()) setHarnessState;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            setHarnessState = setState;
            return SizedBox(
              height: 400,
              child: SingleChildScrollView(
                controller: controller,
                child: VirtualThreadViewport(
                  messages: messages,
                  scrollController: controller,
                  overscan: 1,
                  estimateHeight: 100,
                  onMeasureScrollCorrection: corrections.add,
                  messageBuilder: (_, m) => SizedBox(
                    height: heights[m.id]!,
                    width: double.infinity,
                    child: Text(m.id, key: ValueKey('msg-${m.id}')),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Viewport top at 50 → turn0 (0–100) straddles; must not correct.
    controller.jumpTo(50);
    await tester.pumpAndSettle();
    corrections.clear();

    setHarnessState(() {
      heights['m0'] = 200;
    });
    await tester.pumpAndSettle();

    expect(corrections, isEmpty);
  });
}
