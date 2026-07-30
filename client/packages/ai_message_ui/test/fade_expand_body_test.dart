import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('short child: no expand_more', (tester) async {
    await tester.pumpWidget(_wrap(
      AiFadeExpandBody(
        open: false,
        onToggle: () {},
        fadeColor: Colors.grey,
        child: const SizedBox(height: 40, child: Text('short')),
      ),
    ));
    await tester.pump(); // measure
    expect(find.byIcon(Icons.expand_more), findsNothing);
  });

  testWidgets('overflow collapsed: expand_more; tap toggles once', (tester) async {
    var toggles = 0;
    await tester.pumpWidget(_wrap(
      AiFadeExpandBody(
        open: false,
        onToggle: () => toggles++,
        fadeColor: Colors.grey,
        child: const SizedBox(height: 200, child: Text('tall')),
      ),
    ));
    await tester.pump();
    expect(find.byKey(const ValueKey('ai-fade-expand-chevron')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ai-fade-expand-chevron')));
    await tester.pump();
    expect(toggles, 1);
  });

  testWidgets('overflow expanded mid-height: expand_less present; no scroll viewport', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(
      AiFadeExpandBody(
        open: true,
        onToggle: () {},
        fadeColor: Colors.grey,
        child: const SizedBox(height: 200, child: Text('mid')),
      ),
    ));
    await tester.pump();
    expect(find.byKey(const ValueKey('ai-fade-expand-chevron')), findsOneWidget);
    expect(find.byIcon(Icons.expand_less), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsNothing);
  });

  testWidgets('overflow expanded tall: scrolls under 320 and shows expand_less', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(
      SizedBox(
        width: 300,
        child: AiFadeExpandBody(
          open: true,
          onToggle: () {},
          fadeColor: Colors.grey,
          child: const SizedBox(height: 500, child: Text('very-tall')),
        ),
      ),
    ));
    await tester.pump();
    expect(find.byIcon(Icons.expand_less), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    final box = tester.renderObject<RenderBox>(find.byType(AiFadeExpandBody));
    expect(box.size.height, lessThanOrEqualTo(kAiFadeExpandExpandedMaxHeight + 1));
  });

  testWidgets('opaque chevron does not also fire parent card tap', (tester) async {
    var bodyToggles = 0;
    var cardToggles = 0;
    await tester.pumpWidget(_wrap(
      AiExpandableToolCard(
        open: false,
        onToggle: () => cardToggles++,
        child: AiFadeExpandBody(
          open: false,
          onToggle: () => bodyToggles++,
          fadeColor: Colors.grey,
          child: const SizedBox(height: 200, child: Text('inside-card')),
        ),
      ),
    ));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('ai-fade-expand-chevron')));
    await tester.pump();
    expect(bodyToggles, 1);
    expect(cardToggles, 0); // opaque child absorbs
  });

  testWidgets('collapsed host height stays at collapsed max, not full child', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(
      AiFadeExpandBody(
        open: false,
        onToggle: () {},
        fadeColor: Colors.grey,
        child: const SizedBox(height: 400, child: Text('probe-size')),
      ),
    ));
    await tester.pump();
    final box = tester.renderObject<RenderBox>(find.byType(AiFadeExpandBody));
    expect(box.size.height, closeTo(kAiFadeExpandCollapsedMaxHeight, 1));
  });
}

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));
