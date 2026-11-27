import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The live thinking body keeps its own scroll position inside a max-height
/// box: while the turn streams it follows the newest line, but the user must
/// be able to scroll up and read earlier thinking without being yanked back,
/// and must be able to resume the follow by scrolling back down.
void main() {
  late List<String> lines;

  Widget build({bool churnTheme = false}) => MaterialApp(
    theme: ThemeData(extensions: [AiMessageTheme.test()]),
    home: Scaffold(
      body: Builder(
        builder: (context) {
          Widget body = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AiReasoningPartView(
                part: AiReasoningPart(text: lines.join('\n')),
                initiallyExpanded: true,
                autoFollow: true,
              ),
            ],
          );
          if (churnTheme) {
            // The chat rebuilds a tightened theme for the live tip on every
            // streamed chunk, which re-creates every descendant ScrollPosition
            // (Scrollable.didChangeDependencies → _updatePosition). The follow
            // must survive that.
            final theme = Theme.of(context);
            body = Theme(
              data: theme.copyWith(
                extensions: [
                  ...theme.extensions.values.where((e) => e is! AiMessageTheme),
                  AiMessageTheme.test(messageSpacing: 8),
                ],
              ),
              child: body,
            );
          }
          return body;
        },
      ),
    ),
  );

  Future<void> streamLine(WidgetTester tester, String line) async {
    lines = [...lines, line];
    await tester.pumpWidget(build());
    await tester.pump();
    await tester.pump();
  }

  ScrollPosition livePosition(WidgetTester tester) =>
      tester.state<ScrollableState>(find.byType(Scrollable).first).position;

  Future<void> pumpLive(WidgetTester tester) async {
    lines = List.generate(40, (i) => 'line $i');
    await tester.pumpWidget(build());
    await tester.pump(const Duration(milliseconds: 300));
    await streamLine(tester, 'warm up');
  }

  testWidgets('a live body opens on the newest line', (tester) async {
    lines = List.generate(40, (i) => 'line $i');
    await tester.pumpWidget(build());
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      livePosition(tester).maxScrollExtent - livePosition(tester).pixels,
      lessThan(4.0),
      reason: 'the live body must not open on the first thinking line',
    );
  });

  testWidgets('streaming does not yank the body back while the user reads', (
    tester,
  ) async {
    await pumpLive(tester);
    expect(
      livePosition(tester).maxScrollExtent - livePosition(tester).pixels,
      lessThan(4.0),
      reason: 'the live body follows the newest line by default',
    );

    // User drags up inside the thinking box.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 160));
    await tester.pump(const Duration(milliseconds: 50));
    final readOffset = livePosition(tester).pixels;
    expect(
      livePosition(tester).maxScrollExtent - readOffset,
      greaterThan(20.0),
      reason: 'the drag must move the body away from the tip',
    );

    // The turn keeps streaming.
    await streamLine(tester, 'while reading');

    expect(
      livePosition(tester).pixels,
      closeTo(readOffset, 1.0),
      reason: 'new thinking lines must not pull the reader back down',
    );
  });

  testWidgets('scrolling back to the newest line resumes the follow', (
    tester,
  ) async {
    await pumpLive(tester);

    await tester.drag(find.byType(Scrollable).first, const Offset(0, 160));
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      livePosition(tester).maxScrollExtent - livePosition(tester).pixels,
      greaterThan(20.0),
    );

    // User scrolls back down to the tip.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      livePosition(tester).maxScrollExtent - livePosition(tester).pixels,
      lessThan(4.0),
      reason: 'dragging down must land on the tip',
    );

    await streamLine(tester, 'after return');

    expect(
      livePosition(tester).maxScrollExtent - livePosition(tester).pixels,
      lessThan(4.0),
      reason: 'landing on the tip must re-arm the follow',
    );
  });

  testWidgets('theme churn during a live turn keeps the follow armed', (
    tester,
  ) async {
    // Robustness: any ancestor that rebuilds its ThemeData while the turn is
    // streaming re-creates the descendant ScrollPosition. The follow must
    // survive that (the transcript used to do this on every chunk).
    lines = List.generate(40, (i) => 'line $i');
    await tester.pumpWidget(build(churnTheme: true));
    await tester.pump(const Duration(milliseconds: 300));

    for (var i = 0; i < 4; i++) {
      lines = [...lines, 'chunk $i'];
      await tester.pumpWidget(build(churnTheme: true));
      await tester.pump();
      await tester.pump();
    }

    expect(
      livePosition(tester).maxScrollExtent - livePosition(tester).pixels,
      lessThan(4.0),
      reason: 'a rebuilt theme must not break the thinking follow',
    );
  });

  testWidgets('finished reasoning uses the success status color', (
    tester,
  ) async {
    const successColor = Color(0xFF248A5A);
    final scheme = ColorScheme.fromSeed(seedColor: Colors.blue);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: scheme,
          extensions: [AiMessageTheme.test(toolSuccessColor: successColor)],
        ),
        home: const Scaffold(
          body: AiReasoningPartView(part: AiReasoningPart(text: 'finished')),
        ),
      ),
    );

    expect(find.text('Thought'), findsOneWidget);
    expect(
      tester.widget<Icon>(find.byIcon(Icons.check_circle_outline)).color,
      successColor,
    );
  });

  testWidgets('live reasoning uses the running status color', (tester) async {
    final scheme = ColorScheme.fromSeed(seedColor: Colors.blue);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorScheme: scheme),
        home: const Scaffold(
          body: AiReasoningPartView(
            part: AiReasoningPart(text: 'streaming'),
            initiallyExpanded: true,
            autoFollow: true,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Thinking'), findsOneWidget);
    expect(
      tester
          .widget<CircularProgressIndicator>(
            find.byType(CircularProgressIndicator),
          )
          .color,
      scheme.primary,
    );
  });
}
