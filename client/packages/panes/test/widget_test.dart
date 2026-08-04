import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panes/panes.dart';
import 'package:panes/src/resizer.dart';

void main() {
  group('MultiPane', () {
    testWidgets('renders all visible panes', (tester) async {
      final controller = PaneController(
        entries: [
          PaneEntry(id: 'a', initialSize: PaneSize.pixel(100)),
          PaneEntry(id: 'b', initialSize: PaneSize.fraction(1.0)),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MultiPane(
              direction: Axis.horizontal,
              controller: controller,
              paneBuilder: (context, id, progress) => Container(
                key: Key('pane_$id'),
                color: id == 'a' ? Colors.red : Colors.blue,
              ),
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('pane_a')), findsOneWidget);
      expect(find.byKey(const Key('pane_b')), findsOneWidget);
    });

    testWidgets(
      'pixel pane builder is not invoked on every animation tick',
      (tester) async {
        final controller = PaneController(
          entries: [
            PaneEntry(id: 'a', initialSize: PaneSize.pixel(100)),
            PaneEntry(id: 'b', initialSize: PaneSize.fraction(1.0)),
          ],
        );
        var builds = 0;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MultiPane(
                direction: Axis.horizontal,
                controller: controller,
                animationDuration: const Duration(milliseconds: 200),
                paneBuilder: (context, id, progress) {
                  if (id == 'a') builds++;
                  return Container(key: Key('pane_$id'));
                },
              ),
            ),
          ),
        );

        final afterFirstLayout = builds;
        expect(afterFirstLayout, greaterThan(0));

        // Advance through the open animation without settling.
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 50));

        expect(
          builds,
          afterFirstLayout,
          reason: 'TweenAnimationBuilder must reuse child across ticks',
        );
      },
    );

    testWidgets(
      'paneBuilder is not invoked again on resize deltas',
      (tester) async {
        final controller = PaneController(
          entries: [
            PaneEntry(id: 'a', initialSize: PaneSize.pixel(100)),
            PaneEntry(id: 'b', initialSize: PaneSize.fraction(1.0)),
            PaneEntry(id: 'c', initialSize: PaneSize.pixel(120)),
          ],
        );
        final builds = <String, int>{'a': 0, 'b': 0, 'c': 0};

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 400,
                child: MultiPane(
                  direction: Axis.horizontal,
                  controller: controller,
                  paneBuilder: (context, id, progress) {
                    builds[id] = (builds[id] ?? 0) + 1;
                    return Container(key: Key('pane_$id'));
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final afterLayout = Map<String, int>.from(builds);
        expect(afterLayout['a'], greaterThan(0));
        expect(afterLayout['b'], greaterThan(0));
        expect(afterLayout['c'], greaterThan(0));

        controller.beginResize('a', adjacentPaneId: 'b');
        await tester.pump();
        for (var i = 0; i < 5; i++) {
          controller.resize(
            paneId: 'a',
            delta: 4,
            containerSize: 800,
            resizerThickness: 1,
            adjacentPaneId: 'b',
          );
          await tester.pump();
        }
        controller.endResize('a', adjacentPaneId: 'b');
        await tester.pump();

        expect(
          builds,
          afterLayout,
          reason: 'size-only notifies must reuse pane content',
        );

        // Right-edge style: resize pixel pane next to fraction.
        final beforeRight = Map<String, int>.from(builds);
        controller.beginResize('c', adjacentPaneId: 'b');
        await tester.pump();
        controller.resize(
          paneId: 'c',
          delta: -8,
          containerSize: 800,
          resizerThickness: 1,
          adjacentPaneId: 'b',
        );
        await tester.pump();
        controller.endResize('c', adjacentPaneId: 'b');
        await tester.pump();
        expect(builds, beforeRight);
      },
    );

    testWidgets(
      'paneBuilder runs once on hide, not on size-tween ticks',
      (tester) async {
        final controller = PaneController(
          entries: [
            PaneEntry(id: 'a', initialSize: PaneSize.pixel(100)),
            PaneEntry(id: 'b', initialSize: PaneSize.fraction(1.0)),
          ],
        );
        var buildsA = 0;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MultiPane(
                direction: Axis.horizontal,
                controller: controller,
                animationDuration: const Duration(milliseconds: 200),
                paneBuilder: (context, id, progress) {
                  if (id == 'a') buildsA++;
                  return Container(key: Key('pane_$id'));
                },
              ),
            ),
          ),
        );
        await tester.pump(); // start; do not settle open animation fully

        final afterFirst = buildsA;
        expect(afterFirst, greaterThan(0));

        controller.hide('a');
        await tester.pump(); // apply visibility → progress 0; builder once
        final afterHide = buildsA;
        expect(afterHide, greaterThan(afterFirst));

        await tester.pump(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 50));
        expect(
          buildsA,
          afterHide,
          reason: 'hide size tween must not re-invoke paneBuilder',
        );
      },
    );

    testWidgets(
      'maximize then restore re-invokes paneBuilder',
      (tester) async {
        final controller = PaneController(
          entries: [
            PaneEntry(id: 'a', initialSize: PaneSize.pixel(100)),
            PaneEntry(id: 'b', initialSize: PaneSize.fraction(1.0)),
          ],
        );
        var buildsB = 0;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MultiPane(
                direction: Axis.horizontal,
                controller: controller,
                paneBuilder: (context, id, progress) {
                  if (id == 'b') buildsB++;
                  return Container(key: Key('pane_$id'));
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final baseline = buildsB;

        controller.maximize('b');
        await tester.pump();
        expect(buildsB, greaterThan(baseline));

        final afterMax = buildsB;
        controller.restore();
        await tester.pump();
        expect(buildsB, greaterThan(afterMax));
      },
    );

    testWidgets('does not nest LayoutBuilder around pane content', (
      tester,
    ) async {
      final controller = PaneController(
        entries: [
          PaneEntry(id: 'a', initialSize: PaneSize.pixel(100)),
          PaneEntry(id: 'b', initialSize: PaneSize.fraction(1.0)),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MultiPane(
              direction: Axis.horizontal,
              controller: controller,
              paneBuilder: (context, id, progress) =>
                  Container(key: Key('pane_$id')),
            ),
          ),
        ),
      );

      expect(
        find.descendant(
          of: find.byType(MultiPane),
          matching: find.byType(LayoutBuilder),
        ),
        findsNothing,
      );
      expect(find.byType(PaneSizeReporter), findsOneWidget);
    });

    testWidgets('hides pane via controller', (tester) async {
      final controller = PaneController(
        entries: [
          PaneEntry(id: 'a', initialSize: PaneSize.pixel(100)),
          PaneEntry(id: 'b', initialSize: PaneSize.fraction(1.0)),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MultiPane(
              direction: Axis.horizontal,
              controller: controller,
              paneBuilder: (context, id, progress) => Container(
                key: Key('pane_$id'),
              ),
            ),
          ),
        ),
      );

      expect(controller.isVisible('a'), isTrue);

      controller.hide('a');
      await tester.pumpAndSettle();

      // Pane is hidden (animates to 0 width but stays in tree)
      expect(controller.isVisible('a'), isFalse);
    });

    testWidgets('pixel pane show/hide animates width instead of jumping', (
      tester,
    ) async {
      final controller = PaneController(
        entries: [
          PaneEntry(id: 'a', initialSize: PaneSize.pixel(200)),
          PaneEntry(id: 'b', initialSize: PaneSize.fraction(1.0)),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 400,
              child: MultiPane(
                direction: Axis.horizontal,
                controller: controller,
                animationDuration: const Duration(milliseconds: 200),
                paneBuilder: (context, id, progress) =>
                    Container(key: Key('pane_$id')),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      double paneAWidth() =>
          tester.getSize(find.byKey(const ValueKey('pane-slot-a'))).width;

      expect(paneAWidth(), closeTo(200, 1));

      controller.hide('a');
      await tester.pump(); // start tween
      await tester.pump(const Duration(milliseconds: 50));
      final midHide = paneAWidth();
      expect(midHide, greaterThan(1));
      expect(midHide, lessThan(199));

      await tester.pumpAndSettle();
      expect(paneAWidth(), closeTo(0, 1));

      controller.show('a');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final midShow = paneAWidth();
      expect(midShow, greaterThan(1));
      expect(midShow, lessThan(199));

      await tester.pumpAndSettle();
      expect(paneAWidth(), closeTo(200, 1));
    });

    testWidgets('resizer is focusable and responds to keyboard',
        (tester) async {
      final controller = PaneController(
        entries: [
          PaneEntry(id: 'a', initialSize: PaneSize.pixel(100)),
          PaneEntry(id: 'b', initialSize: PaneSize.fraction(1.0)),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MultiPane(
              direction: Axis.horizontal,
              controller: controller,
              paneBuilder: (context, id, progress) => Container(
                key: Key('pane_$id'),
              ),
            ),
          ),
        ),
      );

      // Find the resizer
      final resizerFinder = find.byType(Resizer);
      expect(resizerFinder, findsOneWidget);

      // Focus the resizer
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();

      // Verify focus (check if the primary focus is within the Resizer)
      final focusedNode = FocusManager.instance.primaryFocus;
      expect(focusedNode, isNotNull);
      expect(
        focusedNode!.context!.findAncestorWidgetOfExactType<Resizer>(),
        isNotNull,
      );

      // Initial size
      final pixelsBefore = controller.getPixelSize('a') ?? 100;

      // Resize using arrow keys (Right arrow = +10)
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();

      final pixelsAfter = controller.getPixelSize('a') ?? 100;
      expect(pixelsAfter, greaterThan(pixelsBefore));
    });

    testWidgets('resizer is tappable and draggable', (tester) async {
      final controller = PaneController(
        entries: [
          PaneEntry(id: 'a', initialSize: PaneSize.pixel(200)),
          PaneEntry(id: 'b', initialSize: PaneSize.fraction(1.0)),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: MultiPane(
                direction: Axis.horizontal,
                controller: controller,
                paneBuilder: (context, id, progress) => Container(
                  key: Key('pane_$id'),
                  color: Colors.grey,
                ),
              ),
            ),
          ),
        ),
      );

      // Find the resizer (MouseRegion with resize cursor)
      final resizer = find.byType(MouseRegion).first;
      expect(resizer, findsOneWidget);
    });

    testWidgets('double-tap resizer resets size', (tester) async {
      final controller = PaneController(
        entries: [
          PaneEntry(id: 'a', initialSize: PaneSize.pixel(100)),
          PaneEntry(id: 'b', initialSize: PaneSize.fraction(1.0)),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: MultiPane(
                direction: Axis.horizontal,
                controller: controller,
                paneBuilder: (context, id, progress) =>
                    Container(key: Key('pane_$id')),
              ),
            ),
          ),
        ),
      );

      // Change size first
      controller.updateSize('a', PaneSize.pixel(200));
      await tester.pumpAndSettle();
      expect(controller.getPixelSize('a'), 200);

      // Find and double-tap the resizer
      final resizer = find.byType(Resizer);
      await tester.tap(resizer);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(resizer);
      await tester.pumpAndSettle();

      // Size should be reset (getPixelSize returns null = initial)
      expect(controller.getPixelSize('a'), isNull);
    });

    test('save and load preserves state', () {
      final controller = PaneController(
        entries: [
          PaneEntry(id: 'a', initialSize: PaneSize.pixel(100)),
          PaneEntry(id: 'b', initialSize: PaneSize.fraction(1.0)),
        ],
      );

      // Modify state
      controller.updateSize('a', PaneSize.pixel(200));
      controller.hide('b');

      // Save
      final saved = controller.save();

      // Create new controller and load
      final controller2 = PaneController(
        entries: [
          PaneEntry(id: 'a', initialSize: PaneSize.pixel(100)),
          PaneEntry(id: 'b', initialSize: PaneSize.fraction(1.0)),
        ],
      );
      controller2.load(saved);

      expect(controller2.getPixelSize('a'), 200);
      expect(controller2.isVisible('b'), isFalse);
    });

    test('maximize and restore works correctly', () {
      final controller = PaneController(
        entries: [
          PaneEntry(id: 'a', initialSize: PaneSize.pixel(100)),
          PaneEntry(id: 'b', initialSize: PaneSize.fraction(1.0)),
        ],
      );

      expect(controller.isMaximized, isFalse);
      expect(controller.maximizedPaneId, isNull);

      controller.maximize('a');
      expect(controller.isMaximized, isTrue);
      expect(controller.maximizedPaneId, 'a');

      controller.restore();
      expect(controller.isMaximized, isFalse);
      expect(controller.maximizedPaneId, isNull);
    });

    test('toggleMaximize toggles between states', () {
      final controller = PaneController(
        entries: [
          PaneEntry(id: 'a', initialSize: PaneSize.pixel(100)),
          PaneEntry(id: 'b', initialSize: PaneSize.fraction(1.0)),
        ],
      );

      controller.toggleMaximize('a');
      expect(controller.isMaximized, isTrue);
      expect(controller.maximizedPaneId, 'a');

      controller.toggleMaximize('a');
      expect(controller.isMaximized, isFalse);
    });

    test('resetSize clears size override', () {
      final controller = PaneController(
        entries: [
          PaneEntry(id: 'a', initialSize: PaneSize.pixel(100)),
          PaneEntry(id: 'b', initialSize: PaneSize.fraction(1.0)),
        ],
      );

      controller.updateSize('a', PaneSize.pixel(200));
      expect(controller.getPixelSize('a'), 200);

      controller.resetSize('a');
      expect(controller.getPixelSize('a'), isNull);
    });

    test('resetAll clears all size overrides', () {
      final controller = PaneController(
        entries: [
          PaneEntry(id: 'a', initialSize: PaneSize.pixel(100)),
          PaneEntry(id: 'b', initialSize: PaneSize.pixel(200)),
        ],
      );

      controller.updateSize('a', PaneSize.pixel(300));
      controller.updateSize('b', PaneSize.pixel(400));

      expect(controller.getPixelSize('a'), 300);
      expect(controller.getPixelSize('b'), 400);

      controller.resetAll();

      expect(controller.getPixelSize('a'), isNull);
      expect(controller.getPixelSize('b'), isNull);
    });
  });

  group('IdeLayout', () {
    testWidgets('renders all panels when visible', (tester) async {
      final controller = IdeController(
        leftSize: PaneSize.pixel(200),
        rightSize: PaneSize.pixel(200),
        bottomSize: PaneSize.pixel(100),
      );

      // Show all panels
      controller.rootController.show(IdePane.right.id);
      controller.centerController.show(IdePane.bottom.id);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1000,
              height: 800,
              child: IdeLayout(
                controller: controller,
                leftPanelBuilder: (context, progress) =>
                    Container(key: const Key('left'), color: Colors.red),
                rightPanelBuilder: (context, progress) =>
                    Container(key: const Key('right'), color: Colors.green),
                bottomPanelBuilder: (context, progress) =>
                    Container(key: const Key('bottom'), color: Colors.blue),
                centerBuilder: (context, progress) =>
                    Container(key: const Key('center'), color: Colors.yellow),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byKey(const Key('left')), findsOneWidget);
      expect(find.byKey(const Key('right')), findsOneWidget);
      expect(find.byKey(const Key('bottom')), findsOneWidget);
      expect(find.byKey(const Key('center')), findsOneWidget);
    });

    testWidgets('toggleLeft hides/shows left panel', (tester) async {
      final controller = IdeController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: IdeLayout(
                controller: controller,
                leftPanelBuilder: (context, progress) =>
                    Container(key: const Key('left')),
                centerBuilder: (context, progress) =>
                    Container(key: const Key('center')),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(controller.rootController.isVisible(IdePane.left.id), isTrue);

      controller.toggleLeft();
      await tester.pumpAndSettle();
      expect(controller.rootController.isVisible(IdePane.left.id), isFalse);

      controller.toggleLeft();
      await tester.pumpAndSettle();
      expect(controller.rootController.isVisible(IdePane.left.id), isTrue);
    });

    test('save and load preserves IdeController state', () {
      final controller = IdeController(
        leftSize: PaneSize.pixel(200),
        rightSize: PaneSize.pixel(200),
        bottomSize: PaneSize.pixel(100),
      );

      // Modify state
      controller.rootController.updateSize(
        IdePane.left.id,
        PaneSize.pixel(300),
      );
      controller.toggleRight();
      controller.toggleBottom();

      // Save
      final saved = controller.save();

      // Create new controller and load
      final controller2 = IdeController();
      controller2.load(saved);

      expect(
        controller2.rootController.getPixelSize(IdePane.left.id),
        300,
      );
      expect(
        controller2.rootController.isVisible(IdePane.right.id),
        isTrue,
      );
      expect(
        controller2.centerController.isVisible(IdePane.bottom.id),
        isTrue,
      );
    });

    test('dispose disposes both controllers', () {
      final controller = IdeController();

      // Should not throw
      controller.dispose();

      // Verify controllers are disposed (listeners cleared)
      // After dispose, adding listeners should still work but the
      // controllers are effectively dead
      expect(
          () => controller.rootController.notifyListeners(), throwsA(anything));
    });
  });

  group('TabbedPane', () {
    testWidgets('renders tabs with labels', (tester) async {
      int selectedIndex = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return TabbedPane(
                  labels: const ['Tab 1', 'Tab 2', 'Tab 3'],
                  selectedIndex: selectedIndex,
                  onTabSelected: (index) {
                    setState(() => selectedIndex = index);
                  },
                  tabBuilder: (context, index) =>
                      Center(child: Text('Content $index')),
                );
              },
            ),
          ),
        ),
      );

      expect(find.text('Tab 1'), findsOneWidget);
      expect(find.text('Tab 2'), findsOneWidget);
      expect(find.text('Tab 3'), findsOneWidget);
      expect(find.text('Content 0'), findsOneWidget);
    });

    testWidgets('switching tabs updates content', (tester) async {
      int selectedIndex = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return TabbedPane(
                  labels: const ['A', 'B'],
                  selectedIndex: selectedIndex,
                  onTabSelected: (index) {
                    setState(() => selectedIndex = index);
                  },
                  tabBuilder: (context, index) =>
                      Center(child: Text('Content $index')),
                );
              },
            ),
          ),
        ),
      );

      expect(find.text('Content 0'), findsOneWidget);

      await tester.tap(find.text('B'));
      await tester.pumpAndSettle();

      expect(find.text('Content 1'), findsOneWidget);
    });

    testWidgets('renders icons when provided', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TabbedPane(
              labels: const ['Home', 'Settings'],
              icons: const [Icons.home, Icons.settings],
              selectedIndex: 0,
              onTabSelected: (_) {},
              tabBuilder: (context, index) => const SizedBox(),
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.home), findsOneWidget);
      expect(find.byIcon(Icons.settings), findsOneWidget);
    });

    testWidgets('actions are rendered', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TabbedPane(
              labels: const ['Tab'],
              selectedIndex: 0,
              onTabSelected: (_) {},
              actions: [
                IconButton(
                  key: const Key('action_btn'),
                  icon: const Icon(Icons.add),
                  onPressed: () {},
                ),
              ],
              tabBuilder: (context, index) => const SizedBox(),
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('action_btn')), findsOneWidget);
    });
  });

  group('PaneTheme', () {
    testWidgets('PaneTheme.of returns theme from inherited widget',
        (tester) async {
      PaneThemeData? capturedTheme;

      await tester.pumpWidget(
        MaterialApp(
          home: PaneTheme(
            data: const PaneThemeData(
              resizerThickness: 10.0,
              tabHeaderColor: Colors.purple,
            ),
            child: Builder(
              builder: (context) {
                capturedTheme = PaneTheme.of(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      expect(capturedTheme, isNotNull);
      expect(capturedTheme!.resizerThickness, 10.0);
      expect(capturedTheme!.tabHeaderColor, Colors.purple);
    });

    testWidgets('falls back to ThemeExtension when no PaneTheme',
        (tester) async {
      PaneThemeData? capturedTheme;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            extensions: const [
              PaneThemeData(
                resizerThickness: 8.0,
                tabBackground: Colors.orange,
              ),
            ],
          ),
          home: Builder(
            builder: (context) {
              capturedTheme = PaneTheme.of(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(capturedTheme, isNotNull);
      expect(capturedTheme!.resizerThickness, 8.0);
      expect(capturedTheme!.tabBackground, Colors.orange);
    });
  });
}
