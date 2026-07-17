import 'package:flutter_test/flutter_test.dart';
import 'package:panes/panes.dart';
import 'package:panes/src/auto_hide_state.dart';
import 'package:panes/src/resize_calculator.dart';

void main() {
  group('Max overshoot behavior', () {
    late PaneController controller;

    setUp(() {
      controller = PaneController(
        entries: [
          PaneEntry(
            id: 'left',
            initialSize: PaneSize.pixel(200),
            minSize: PaneSize.pixel(100),
            maxSize: PaneSize.pixel(300),
          ),
          PaneEntry(
            id: 'right',
            initialSize: PaneSize.fraction(1.0),
          ),
        ],
      );
    });

    test('dragging past max clamps display at max', () {
      controller.beginResize('left', adjacentPaneId: 'right');

      // Drag from 200 to 350 (past max of 300)
      controller.resize(
        paneId: 'left',
        delta: 150,
        containerSize: 800,
        resizerThickness: 8,
        adjacentPaneId: 'right',
      );

      // Display should be clamped at max
      expect(controller.getVisualPixelSize('left'), 300);
    });

    test('reversing while still past max does NOT resize', () {
      controller.beginResize('left', adjacentPaneId: 'right');

      // Drag to 350 (past max of 300)
      controller.resize(
        paneId: 'left',
        delta: 150,
        containerSize: 800,
        resizerThickness: 8,
        adjacentPaneId: 'right',
      );
      expect(controller.getVisualPixelSize('left'), 300);

      // Reverse by 30px: virtual goes from 350 to 320, still > max
      controller.resize(
        paneId: 'left',
        delta: -30,
        containerSize: 800,
        resizerThickness: 8,
        adjacentPaneId: 'right',
      );

      // Should still be at max, not 270
      expect(controller.getVisualPixelSize('left'), 300);
    });

    test('reversing back into bounds resizes to actual position', () {
      controller.beginResize('left', adjacentPaneId: 'right');

      // Drag to 350 (past max of 300)
      controller.resize(
        paneId: 'left',
        delta: 150,
        containerSize: 800,
        resizerThickness: 8,
        adjacentPaneId: 'right',
      );

      // Reverse by 70px: virtual goes from 350 to 280, now < max
      controller.resize(
        paneId: 'left',
        delta: -70,
        containerSize: 800,
        resizerThickness: 8,
        adjacentPaneId: 'right',
      );

      // Should resize to 280
      expect(controller.getVisualPixelSize('left'), 280);
    });

    test('continued dragging past max accumulates virtual position', () {
      controller.beginResize('left', adjacentPaneId: 'right');

      // Drag to 350
      controller.resize(
        paneId: 'left',
        delta: 150,
        containerSize: 800,
        resizerThickness: 8,
        adjacentPaneId: 'right',
      );

      // Drag another 100 to virtual 450
      controller.resize(
        paneId: 'left',
        delta: 100,
        containerSize: 800,
        resizerThickness: 8,
        adjacentPaneId: 'right',
      );

      // Display still at max
      expect(controller.getVisualPixelSize('left'), 300);

      // Reverse 100px: virtual 450 -> 350, still > max
      controller.resize(
        paneId: 'left',
        delta: -100,
        containerSize: 800,
        resizerThickness: 8,
        adjacentPaneId: 'right',
      );
      expect(controller.getVisualPixelSize('left'), 300);

      // Reverse another 100px: virtual 350 -> 250, now < max
      controller.resize(
        paneId: 'left',
        delta: -100,
        containerSize: 800,
        resizerThickness: 8,
        adjacentPaneId: 'right',
      );
      expect(controller.getVisualPixelSize('left'), 250);
    });

    test('endResize clears overshoot tracking', () {
      controller.beginResize('left', adjacentPaneId: 'right');

      // Drag to 350 (past max)
      controller.resize(
        paneId: 'left',
        delta: 150,
        containerSize: 800,
        resizerThickness: 8,
        adjacentPaneId: 'right',
      );
      expect(controller.getVisualPixelSize('left'), 300);

      // End resize
      controller.endResize('left', adjacentPaneId: 'right');

      // Start new resize
      controller.beginResize('left', adjacentPaneId: 'right');

      // Small reverse should resize immediately (no accumulated overshoot)
      controller.resize(
        paneId: 'left',
        delta: -20,
        containerSize: 800,
        resizerThickness: 8,
        adjacentPaneId: 'right',
      );
      expect(controller.getVisualPixelSize('left'), 280);
    });
  });

  group('Min undershoot behavior (non-autoHide)', () {
    late PaneController controller;

    setUp(() {
      controller = PaneController(
        entries: [
          PaneEntry(
            id: 'left',
            initialSize: PaneSize.pixel(200),
            minSize: PaneSize.pixel(100),
            maxSize: PaneSize.pixel(300),
            // autoHide: false (default)
          ),
          PaneEntry(
            id: 'right',
            initialSize: PaneSize.fraction(1.0),
          ),
        ],
      );
    });

    test('dragging below min clamps display at min', () {
      controller.beginResize('left', adjacentPaneId: 'right');

      // Drag from 200 to 50 (below min of 100)
      controller.resize(
        paneId: 'left',
        delta: -150,
        containerSize: 800,
        resizerThickness: 8,
        adjacentPaneId: 'right',
      );

      // Display should be clamped at min
      expect(controller.getVisualPixelSize('left'), 100);
    });

    test('reversing while still below min does NOT resize', () {
      controller.beginResize('left', adjacentPaneId: 'right');

      // Drag to 50 (below min of 100)
      controller.resize(
        paneId: 'left',
        delta: -150,
        containerSize: 800,
        resizerThickness: 8,
        adjacentPaneId: 'right',
      );
      expect(controller.getVisualPixelSize('left'), 100);

      // Reverse by 30px: virtual goes from 50 to 80, still < min
      controller.resize(
        paneId: 'left',
        delta: 30,
        containerSize: 800,
        resizerThickness: 8,
        adjacentPaneId: 'right',
      );

      // Should still be at min, not 130
      expect(controller.getVisualPixelSize('left'), 100);
    });

    test('reversing back into bounds resizes to actual position', () {
      controller.beginResize('left', adjacentPaneId: 'right');

      // Drag to 50 (below min of 100)
      controller.resize(
        paneId: 'left',
        delta: -150,
        containerSize: 800,
        resizerThickness: 8,
        adjacentPaneId: 'right',
      );

      // Reverse by 70px: virtual goes from 50 to 120, now > min
      controller.resize(
        paneId: 'left',
        delta: 70,
        containerSize: 800,
        resizerThickness: 8,
        adjacentPaneId: 'right',
      );

      // Should resize to 120
      expect(controller.getVisualPixelSize('left'), 120);
    });

    test('endResize clears undershoot tracking', () {
      controller.beginResize('left', adjacentPaneId: 'right');

      // Drag to 50 (below min)
      controller.resize(
        paneId: 'left',
        delta: -150,
        containerSize: 800,
        resizerThickness: 8,
        adjacentPaneId: 'right',
      );
      expect(controller.getVisualPixelSize('left'), 100);

      // End resize
      controller.endResize('left', adjacentPaneId: 'right');

      // Start new resize
      controller.beginResize('left', adjacentPaneId: 'right');

      // Small grow should resize immediately (no accumulated undershoot)
      controller.resize(
        paneId: 'left',
        delta: 20,
        containerSize: 800,
        resizerThickness: 8,
        adjacentPaneId: 'right',
      );
      expect(controller.getVisualPixelSize('left'), 120);
    });
  });

  group('Max overshoot with autoHide panes', () {
    late PaneController controller;

    setUp(() {
      controller = PaneController(
        entries: [
          PaneEntry(
            id: 'left',
            initialSize: PaneSize.pixel(200),
            minSize: PaneSize.pixel(100),
            maxSize: PaneSize.pixel(300),
            autoHide: true, // autoHide enabled like IdeController
          ),
          PaneEntry(
            id: 'right',
            initialSize: PaneSize.fraction(1.0),
          ),
        ],
      );
    });

    test('autoHide pane: reversing while past max does NOT resize', () {
      controller.beginResize('left', adjacentPaneId: 'right');

      // Drag to 350 (past max of 300)
      controller.resize(
        paneId: 'left',
        delta: 150,
        containerSize: 800,
        resizerThickness: 8,
        adjacentPaneId: 'right',
      );
      expect(controller.getVisualPixelSize('left'), 300);

      // Reverse by 30px: virtual goes from 350 to 320, still > max
      controller.resize(
        paneId: 'left',
        delta: -30,
        containerSize: 800,
        resizerThickness: 8,
        adjacentPaneId: 'right',
      );

      // Should still be at max, not 270
      expect(controller.getVisualPixelSize('left'), 300);
    });

    test('autoHide pane: reversing back into bounds resizes', () {
      controller.beginResize('left', adjacentPaneId: 'right');

      // Drag to 350 (past max of 300)
      controller.resize(
        paneId: 'left',
        delta: 150,
        containerSize: 800,
        resizerThickness: 8,
        adjacentPaneId: 'right',
      );

      // Reverse by 70px: virtual goes from 350 to 280, now < max
      controller.resize(
        paneId: 'left',
        delta: -70,
        containerSize: 800,
        resizerThickness: 8,
        adjacentPaneId: 'right',
      );

      // Should resize to 280
      expect(controller.getVisualPixelSize('left'), 280);
    });
  });

  group('AutoHide behavior', () {
    late ResizeContext context;
    late PaneEntry entry;

    setUp(() {
      // Standard context: 800px container, minSize=100px
      context = const ResizeContext(
        containerSize: 800,
        resizerThickness: 8,
        resizerCount: 1,
        totalFlexSum: 1.0,
        totalFixedSize: 200,
      );

      entry = PaneEntry(
        id: 'test',
        initialSize: PaneSize.pixel(200),
        minSize: PaneSize.pixel(100),
        autoHide: true,
        // No explicit autoHideThreshold - should default to 50% of minSize = 50px
      );
    });

    test('threshold defaults to half of minSize', () {
      final threshold = ResizeCalculator.getAutoHideThreshold(entry, context);
      expect(threshold, 50.0); // 100 * 0.5
    });

    test('explicit pixel threshold is used when provided', () {
      final entryWithThreshold = entry.copyWith(
        autoHideThreshold: PaneSize.pixel(30),
      );
      final threshold =
          ResizeCalculator.getAutoHideThreshold(entryWithThreshold, context);
      expect(threshold, 30.0);
    });

    test('fractional threshold is interpreted as fraction of minSize', () {
      // minSize = 100px, threshold = 0.5 fraction
      // Should be 100 * 0.5 = 50px, NOT 0.5 * flexSpace
      final entryWithThreshold = entry.copyWith(
        autoHideThreshold: PaneSize.fraction(0.5),
      );
      final threshold =
          ResizeCalculator.getAutoHideThreshold(entryWithThreshold, context);
      expect(threshold, 50.0); // 100 * 0.5, not flexSpace * 0.5
    });

    test('dragging above minSize updates size normally', () {
      final result = AutoHideBehavior.processResize(
        currentState: const AutoHideVisible(pixelSize: 200),
        requestedSize: 150, // Above min (100)
        entry: entry,
        context: context,
        isVisible: true,
      );

      expect(result, isA<AutoHideResultUpdated>());
      final updated = result as AutoHideResultUpdated;
      expect(updated.newSize, 150);
      expect(updated.newState, isA<AutoHideVisible>());
    });

    test('dragging below minSize but above threshold clamps to minSize', () {
      final result = AutoHideBehavior.processResize(
        currentState: const AutoHideVisible(pixelSize: 200),
        requestedSize: 80, // Below min (100), above threshold (50)
        entry: entry,
        context: context,
        isVisible: true,
      );

      expect(result, isA<AutoHideResultUpdated>());
      final updated = result as AutoHideResultUpdated;
      expect(updated.newSize, 100); // Clamped to minSize
      expect(updated.newState, isA<AutoHideDraggingBelowMin>());

      final state = updated.newState as AutoHideDraggingBelowMin;
      expect(state.displaySize, 100); // Visual stays at min
      expect(state.virtualSize, 80); // Tracks actual drag position
    });

    test('dragging below threshold hides the pane', () {
      final result = AutoHideBehavior.processResize(
        currentState: const AutoHideVisible(pixelSize: 200),
        requestedSize: 40, // Below threshold (50)
        entry: entry,
        context: context,
        isVisible: true,
      );

      expect(result, isA<AutoHideResultHide>());
      final hide = result as AutoHideResultHide;
      expect(hide.newState, isA<AutoHidePendingReveal>());

      final state = hide.newState as AutoHidePendingReveal;
      expect(state.restoreSize, 200); // Remember original size
      expect(state.virtualPosition, 40);
    });

    test('continued dragging below min stays clamped at min', () {
      // First drag below min
      var result = AutoHideBehavior.processResize(
        currentState: const AutoHideVisible(pixelSize: 200),
        requestedSize: 80,
        entry: entry,
        context: context,
        isVisible: true,
      );

      expect(result, isA<AutoHideResultUpdated>());
      var state = (result as AutoHideResultUpdated).newState;

      // Continue dragging to 60 (still above threshold)
      result = AutoHideBehavior.processResize(
        currentState: state,
        requestedSize: 60,
        entry: entry,
        context: context,
        isVisible: true,
      );

      expect(result, isA<AutoHideResultUpdated>());
      final updated = result as AutoHideResultUpdated;
      expect(updated.newSize, 100); // Still clamped to min
      expect((updated.newState as AutoHideDraggingBelowMin).virtualSize, 60);
    });

    test('drag-to-reveal: dragging back by threshold reveals pane', () {
      // Start in pending reveal state (pane was hidden)
      const pendingState = AutoHidePendingReveal(
        restoreSize: 200,
        virtualPosition: 30,
        lowestPoint: 30,
      );

      // Drag back by threshold amount (50px from lowest point)
      final result = AutoHideBehavior.processResize(
        currentState: pendingState,
        requestedSize: 80, // 30 + 50 = 80 (threshold reached)
        entry: entry,
        context: context,
        isVisible: false,
      );

      expect(result, isA<AutoHideResultReveal>());
      final reveal = result as AutoHideResultReveal;
      expect(reveal.revealSize, 100); // Clamped to minSize
    });

    test('drag-to-reveal: small reverse drag does not reveal', () {
      const pendingState = AutoHidePendingReveal(
        restoreSize: 200,
        virtualPosition: 30,
        lowestPoint: 30,
      );

      // Small drag back (only 20px, threshold is 50px)
      final result = AutoHideBehavior.processResize(
        currentState: pendingState,
        requestedSize: 50, // 30 + 20 = 50 (below threshold)
        entry: entry,
        context: context,
        isVisible: false,
      );

      expect(result, isA<AutoHideResultNoChange>());
    });
  });

  group('Auto-hide and reveal drift test', () {
    late PaneController controller;

    setUp(() {
      controller = PaneController(
        entries: [
          PaneEntry(
            id: 'left',
            initialSize: PaneSize.pixel(200),
            minSize: PaneSize.pixel(100),
            maxSize: PaneSize.pixel(300),
            autoHide: true,
            // threshold defaults to 50% of minSize = 50px
          ),
          PaneEntry(
            id: 'right',
            initialSize: PaneSize.fraction(1.0),
          ),
        ],
      );
    });

    test('hide then reveal maintains correct size (no drift)', () {
      controller.beginResize('left', adjacentPaneId: 'right');

      // Simulate continuous drag: start at 200px
      // Drag left by -160px (to virtual 40px, below threshold of 50px)
      controller.resize(
        paneId: 'left',
        delta: -160,
        containerSize: 800,
        resizerThickness: 8,
        adjacentPaneId: 'right',
      );

      // Panel should be hidden (40 < 50 threshold)
      expect(controller.isVisible('left'), false);

      // Reverse drag by +60px (to virtual 100px, reverseDelta = 60 >= threshold)
      controller.resize(
        paneId: 'left',
        delta: 60,
        containerSize: 800,
        resizerThickness: 8,
        adjacentPaneId: 'right',
      );

      // Panel should be revealed at minSize (100px)
      expect(controller.isVisible('left'), true);
      expect(controller.getVisualPixelSize('left'), 100);
    });

    test('multiple hide/reveal cycles maintain alignment', () {
      controller.beginResize('left', adjacentPaneId: 'right');

      // First hide: drag -160px (to 40, below threshold)
      controller.resize(
        paneId: 'left',
        delta: -160,
        containerSize: 800,
        resizerThickness: 8,
        adjacentPaneId: 'right',
      );
      expect(controller.isVisible('left'), false);

      // First reveal: drag +60px (to 100, reverseDelta = 60 > threshold)
      controller.resize(
        paneId: 'left',
        delta: 60,
        containerSize: 800,
        resizerThickness: 8,
        adjacentPaneId: 'right',
      );
      expect(controller.isVisible('left'), true);
      expect(controller.getVisualPixelSize('left'), 100);

      // Second hide: drag -60px (to 40, below threshold again)
      controller.resize(
        paneId: 'left',
        delta: -60,
        containerSize: 800,
        resizerThickness: 8,
        adjacentPaneId: 'right',
      );
      expect(controller.isVisible('left'), false);

      // Second reveal: drag +80px (to 120)
      controller.resize(
        paneId: 'left',
        delta: 80,
        containerSize: 800,
        resizerThickness: 8,
        adjacentPaneId: 'right',
      );
      expect(controller.isVisible('left'), true);
      expect(controller.getVisualPixelSize('left'), 120);
    });

    test('reveal at clamped minSize tracks undershoot to prevent drift', () {
      controller.beginResize('left', adjacentPaneId: 'right');

      // Drag to 30px (below threshold of 50px), panel hides
      controller.resize(
        paneId: 'left',
        delta: -170,
        containerSize: 800,
        resizerThickness: 8,
        adjacentPaneId: 'right',
      );
      expect(controller.isVisible('left'), false);

      // Reverse by exactly threshold (50px) to position 80px
      // But minSize is 100px, so reveal will be CLAMPED
      controller.resize(
        paneId: 'left',
        delta: 50,
        containerSize: 800,
        resizerThickness: 8,
        adjacentPaneId: 'right',
      );

      // Panel reveals at minSize (100px), not at mouse position (80px)
      expect(controller.isVisible('left'), true);
      expect(controller.getVisualPixelSize('left'), 100);

      // Now drag +20px more - this should NOT resize yet
      // because we're still in undershoot (mouse at 100, visual at 100)
      controller.resize(
        paneId: 'left',
        delta: 20,
        containerSize: 800,
        resizerThickness: 8,
        adjacentPaneId: 'right',
      );

      // Visual should still be at 100 (catching up from undershoot)
      expect(controller.getVisualPixelSize('left'), 100);

      // Drag +20px more - now we should start resizing (mouse at 120)
      controller.resize(
        paneId: 'left',
        delta: 20,
        containerSize: 800,
        resizerThickness: 8,
        adjacentPaneId: 'right',
      );

      // Now visual should be 120 (past the undershoot catch-up)
      expect(controller.getVisualPixelSize('left'), 120);
    });
  });
}
