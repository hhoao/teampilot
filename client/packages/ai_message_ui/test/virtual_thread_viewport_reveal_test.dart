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
  testWidgets('revealing a message emits its pixel offset post-frame', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final offsets = <double>[];
    var epoch = 0;

    Future<void> pump() async {
      await tester.pumpWidget(
        MaterialApp(
          home: SingleChildScrollView(
            controller: controller,
            child: VirtualThreadViewport(
              messages: _messages(20),
              scrollController: controller,
              mountTurns: true,
              // Mirrors SessionHistoryThread: retain+fill keeps the window
              // monotonic so measurement syncs never shrink it and pumpAndSettle
              // terminates once the fill reaches the full data window.
              retainMountedTurns: true,
              fillDataWindow: true,
              messageBuilder: (context, message) => SizedBox(
                height: 40,
                child: Text(message.id),
              ),
              onRevealOffset: offsets.add,
              revealMessageId: 'm-15',
              revealEpoch: ++epoch,
            ),
          ),
        ),
      );
    }

    // Initial build seeds the last-seen (revealMessageId, revealEpoch), so the
    // first frame must not fire the reveal.
    await pump();
    await tester.pumpAndSettle();
    expect(offsets, isEmpty);

    // Bumping revealEpoch is the host's re-trigger: the post-frame callback
    // emits the estimate-based pixel offset of the turn holding m-15.
    await pump();
    await tester.pumpAndSettle();

    expect(offsets, isNotEmpty);
    expect(offsets.last, greaterThan(0));
  });
}
