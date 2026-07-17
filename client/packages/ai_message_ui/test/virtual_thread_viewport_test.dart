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

Widget _harness({
  required List<AiMessage> messages,
  required ScrollController controller,
  int overscan = 2,
  double estimateHeight = 100,
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
          messageBuilder: (_, m) => SizedBox(
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
}
