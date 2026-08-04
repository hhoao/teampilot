import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SelectedContent;
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

  testWidgets('clip-until-measured short child is not forced to collapsed max', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(
      AiFadeExpandBody(
        open: false,
        onToggle: () {},
        fadeColor: Colors.grey,
        child: const SizedBox(height: 40, child: Text('short')),
      ),
    ));
    final box = tester.renderObject<RenderBox>(find.byType(AiFadeExpandBody));
    expect(box.size.height, lessThan(kAiFadeExpandCollapsedMaxHeight));
    await tester.pump();
    expect(box.size.height, lessThan(kAiFadeExpandCollapsedMaxHeight));
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

  testWidgets('overflow expanded mid-height: expand_less present; capped scroll shell', (
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
    // Open always uses a capped scroll shell (avoids tall-content flash).
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    final box = tester.renderObject<RenderBox>(find.byType(AiFadeExpandBody));
    expect(box.size.height, lessThanOrEqualTo(200 + kAiFadeExpandHitStripHeight + 1));
  });

  testWidgets(
    'expand short→tall child: first open frame stays within expanded max',
    (tester) async {
      var open = false;
      late void Function(void Function()) setState;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, ss) {
                setState = ss;
                return SizedBox(
                  width: 300,
                  child: AiFadeExpandBody(
                    open: open,
                    onToggle: () {},
                    fadeColor: Colors.grey,
                    forceChrome: !open,
                    child: open
                        ? const SizedBox(height: 500, child: Text('tall'))
                        : const SizedBox(height: 40, child: Text('short')),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();

      setState(() => open = true);
      // First frame only — must not flash full 500px before scroll path.
      await tester.pump();

      final box =
          tester.renderObject<RenderBox>(find.byType(AiFadeExpandBody));
      expect(
        box.size.height,
        lessThanOrEqualTo(kAiFadeExpandExpandedMaxHeight + 1),
      );
      expect(find.byType(SingleChildScrollView), findsOneWidget);
    },
  );

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

  testWidgets(
    'collapsed overflow mounts child once and clips host to collapsed max',
    (tester) async {
      await tester.pumpWidget(_wrap(
        AiFadeExpandBody(
          open: false,
          onToggle: () {},
          fadeColor: Colors.grey,
          child: const SizedBox(height: 400, child: Text('clip-me')),
        ),
      ));
      await tester.pump();

      // Single mount (no probe duplicate).
      expect(find.text('clip-me'), findsOneWidget);
      final box = tester.renderObject<RenderBox>(find.byType(AiFadeExpandBody));
      expect(box.size.height, closeTo(kAiFadeExpandCollapsedMaxHeight, 1));
      expect(find.byKey(const ValueKey('ai-fade-expand-chevron')), findsOneWidget);
      // Collapsed clip must not use a scrollable viewport.
      expect(find.byType(Scrollable), findsNothing);
    },
  );

  testWidgets('pointer on fade strip does not select body text', (tester) async {
    var toggles = 0;
    SelectedContent? selection;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SelectionArea(
            onSelectionChanged: (value) => selection = value,
            child: SizedBox(
              width: 280,
              child: AiFadeExpandBody(
                open: false,
                onToggle: () => toggles++,
                fadeColor: Colors.grey,
                child: const Text(
                  'alpha beta gamma delta epsilon zeta eta theta '
                  'iota kappa lambda mu nu xi omicron pi rho sigma',
                  style: TextStyle(fontSize: 16, height: 1.4),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final chevron = find.byKey(const ValueKey('ai-fade-expand-chevron'));
    final maskCenter = tester.getCenter(chevron);

    // Mouse drag across the mask (common desktop select gesture).
    final gesture = await tester.startGesture(
      maskCenter,
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(80, 0));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(
      selection?.plainText,
      isNull,
      reason: 'dragging on the fade mask must not select body text underneath',
    );

    await tester.tap(chevron);
    await tester.pump();
    expect(toggles, 1);
  });

  testWidgets('hover brightens fade strip', (tester) async {
    await tester.pumpWidget(_wrap(
      AiFadeExpandBody(
        open: false,
        onToggle: () {},
        fadeColor: const Color(0xFF808080),
        child: const SizedBox(height: 200, child: Text('tall')),
      ),
    ));
    await tester.pump();

    Color? endColor() {
      final boxes = tester.widgetList<DecoratedBox>(find.byType(DecoratedBox));
      for (final box in boxes) {
        final deco = box.decoration;
        if (deco is BoxDecoration && deco.gradient is LinearGradient) {
          return deco.gradient!.colors.last;
        }
      }
      return null;
    }

    final idle = endColor();
    expect(idle, isNotNull);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(
      tester.getCenter(find.byKey(const ValueKey('ai-fade-expand-chevron'))),
    );
    await tester.pump();

    final hovered = endColor();
    expect(hovered, isNotNull);
    expect(hovered, isNot(idle));
  });

  testWidgets(
    'contentPadding: fade strip flush to host left/right/bottom',
    (tester) async {
      const pad = EdgeInsets.symmetric(horizontal: 16, vertical: 10);
      await tester.pumpWidget(_wrap(
        AiFadeExpandBody(
          open: false,
          onToggle: () {},
          fadeColor: Colors.grey,
          contentPadding: pad,
          child: const SizedBox(height: 200, child: Text('tall')),
        ),
      ));
      await tester.pump();

      final hostBox =
          tester.renderObject<RenderBox>(find.byType(AiFadeExpandBody));
      final hostOrigin = hostBox.localToGlobal(Offset.zero);

      final stripFinder = find.descendant(
        of: find.byType(AiFadeExpandBody),
        matching: find.byWidgetPredicate(
          (w) =>
              w is SizedBox &&
              w.height == kAiFadeExpandHitStripHeight &&
              w.width == double.infinity,
        ),
      );
      expect(stripFinder, findsOneWidget);
      final stripBox = tester.renderObject<RenderBox>(stripFinder);
      final stripOrigin = stripBox.localToGlobal(Offset.zero);

      expect(stripOrigin.dx, closeTo(hostOrigin.dx, 0.5));
      expect(stripBox.size.width, closeTo(hostBox.size.width, 0.5));
      expect(
        stripOrigin.dy + stripBox.size.height,
        closeTo(hostOrigin.dy + hostBox.size.height, 0.5),
      );
    },
  );

  testWidgets(
    'contentPadding + collapsed overflow: host height includes padding',
    (tester) async {
      const pad = EdgeInsets.all(10);
      await tester.pumpWidget(_wrap(
        AiFadeExpandBody(
          open: false,
          onToggle: () {},
          fadeColor: Colors.grey,
          contentPadding: pad,
          child: const SizedBox(height: 400, child: Text('tall')),
        ),
      ));
      await tester.pump();

      final box =
          tester.renderObject<RenderBox>(find.byType(AiFadeExpandBody));
      expect(
        box.size.height,
        closeTo(
          kAiFadeExpandCollapsedMaxHeight + pad.vertical,
          1,
        ),
      );
    },
  );
}

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));
