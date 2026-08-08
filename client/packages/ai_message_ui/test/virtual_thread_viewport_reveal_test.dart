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

  testWidgets(
    'revealed offset is document-space and includes the header height',
    (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      final offsets = <double>[];
      var epoch = 0;
      const headerHeight = 100.0;

      Future<void> pump({String? revealId}) async {
        await tester.pumpWidget(
          MaterialApp(
            home: SingleChildScrollView(
              controller: controller,
              child: VirtualThreadViewport(
                messages: _messages(20),
                scrollController: controller,
                // Estimate matches the real 40px turn height so the cache
                // offset is exact whether or not a turn has been measured.
                estimateHeight: 40,
                mountTurns: true,
                header: const SizedBox(
                  height: headerHeight,
                  width: double.infinity,
                  child: Text('HEADER'),
                ),
                messageBuilder: (context, message) => SizedBox(
                  height: 40,
                  child: Text(message.id),
                ),
                onRevealOffset: offsets.add,
                revealMessageId: revealId ?? 'm-0',
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

      // m-0 is the first turn, which starts right after the header. Its
      // document-space offset must be the measured header height (100), not 0 —
      // without the + _headerHeight term the callback would report 0 and fail.
      await pump();
      await tester.pumpAndSettle();
      expect(offsets, isNotEmpty);
      expect(offsets.last, closeTo(headerHeight, 0.001));

      // m-15 is the 16th turn; each turn contributes 40px, so the document
      // offset is header (100) + 15*40 = 700.
      offsets.clear();
      await pump(revealId: 'm-15');
      await tester.pumpAndSettle();
      expect(offsets.last, closeTo(headerHeight + 15 * 40, 0.001));
    },
  );

  testWidgets(
    'buildKey change re-runs cached messageBuilder (same message list)',
    (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      // Same instance across rebuilds — the normal find-navigation case where
      // the seat's loaded list does not change.
      final messages = _messages(20);
      var builds = 0;

      Future<void> pump(Object? buildKey) async {
        await tester.pumpWidget(
          MaterialApp(
            home: SingleChildScrollView(
              controller: controller,
              child: VirtualThreadViewport(
                messages: messages,
                scrollController: controller,
                mountTurns: true,
                // Mirrors SessionHistoryThread: retain+fill keeps the window
                // monotonic so measurement syncs never shrink it and
                // pumpAndSettle terminates once fill reaches the data window.
                retainMountedTurns: true,
                fillDataWindow: true,
                buildKey: buildKey,
                messageBuilder: (context, message) {
                  builds++;
                  return SizedBox(height: 40, child: Text(message.id));
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      // buildKey must be a real message id in the transcript: invalidation is
      // scoped to the turn that contains the highlight, so a key that matches
      // no message must not invalidate any cached turn body.
      await pump('m-5');
      final buildsAfterA = builds;
      expect(buildsAfterA, greaterThan(0));

      // Same messages instance, only buildKey changed. The cached turn body
      // holding the new highlight must be invalidated so the builder re-runs
      // (the highlight ring's host state changed even though the transcript is
      // unchanged).
      await pump('m-15');
      expect(builds, greaterThan(buildsAfterA));
    },
  );
}
