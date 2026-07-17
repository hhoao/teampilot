import 'package:flutter_test/flutter_test.dart';
import 'package:panes/panes.dart';

void main() {
  group('ResizeBehavior defaults', () {
    test('pixel pane defaults to fixed', () {
      final entry = PaneEntry(
        id: 'pixel',
        initialSize: PaneSize.pixel(100),
      );
      expect(entry.effectiveResizeBehavior, ResizeBehavior.fixed);
    });

    test('fractional pane defaults to eager', () {
      final entry = PaneEntry(
        id: 'fraction',
        initialSize: PaneSize.fraction(1.0),
      );
      expect(entry.effectiveResizeBehavior, ResizeBehavior.eager);
    });

    test('explicit behavior overrides default for pixel pane', () {
      final entry = PaneEntry(
        id: 'pixel',
        initialSize: PaneSize.pixel(100),
        resizeBehavior: ResizeBehavior.eager,
      );
      expect(entry.effectiveResizeBehavior, ResizeBehavior.eager);
    });

    test('explicit behavior overrides default for fractional pane', () {
      final entry = PaneEntry(
        id: 'fraction',
        initialSize: PaneSize.fraction(1.0),
        resizeBehavior: ResizeBehavior.fixed,
      );
      expect(entry.effectiveResizeBehavior, ResizeBehavior.fixed);
    });

    test('copyWith preserves resizeBehavior', () {
      final entry = PaneEntry(
        id: 'test',
        initialSize: PaneSize.pixel(100),
        resizeBehavior: ResizeBehavior.reluctant,
      );
      final copy = entry.copyWith(id: 'copy');
      expect(copy.resizeBehavior, ResizeBehavior.reluctant);
    });
  });

  group('Cascade resize', () {
    const containerSize = 1000.0;
    const resizerThickness = 4.0;

    test('pixel pane clamped to max on overshoot', () {
      // Layout: [pixel:100, max:150] [fraction:1.0] [fraction:1.0]
      // When pixel pane overshoots, it's clamped to max.
      // Fractional panes don't get explicit sizes - flex layout handles it.
      final controller = PaneController(
        entries: [
          PaneEntry(
            id: 'left',
            initialSize: PaneSize.pixel(100),
            maxSize: PaneSize.pixel(150),
            resizeBehavior: ResizeBehavior.eager,
          ),
          PaneEntry(
            id: 'middle',
            initialSize: PaneSize.fraction(1.0),
          ),
          PaneEntry(
            id: 'right',
            initialSize: PaneSize.fraction(1.0),
          ),
        ],
      );

      // Initial sizes
      expect(controller.getPixelSize('left'), isNull); // Uses initial

      // Resize left pane by 100 (would exceed max of 150 by 50)
      controller.resize(
        paneId: 'left',
        delta: 100,
        containerSize: containerSize,
        resizerThickness: resizerThickness,
      );

      // Left pane should be clamped at max
      expect(controller.getPixelSize('left'), 150);

      // Fractional panes should NOT have explicit sizes set
      // The flex layout automatically handles redistribution
      expect(controller.getFractionalSize('middle'), isNull);
      expect(controller.getFractionalSize('right'), isNull);
    });

    test('fixed pixel panes are skipped in cascade', () {
      // Layout: [eager pixel:100] [fixed pixel:200] [eager pixel:300]
      // Only pixel panes participate in cascade, not fractional ones
      final controller = PaneController(
        entries: [
          PaneEntry(
            id: 'left',
            initialSize: PaneSize.pixel(100),
            maxSize: PaneSize.pixel(150),
            resizeBehavior: ResizeBehavior.eager,
          ),
          PaneEntry(
            id: 'middle',
            initialSize: PaneSize.pixel(200),
            resizeBehavior: ResizeBehavior.fixed,
          ),
          PaneEntry(
            id: 'right',
            initialSize: PaneSize.pixel(300),
            minSize: PaneSize.pixel(200),
            resizeBehavior: ResizeBehavior.eager,
          ),
        ],
      );

      // Resize left pane past its max
      controller.resize(
        paneId: 'left',
        delta: 100,
        containerSize: containerSize,
        resizerThickness: resizerThickness,
      );

      // Left pane should be at max
      expect(controller.getPixelSize('left'), 150);

      // Middle (fixed) pane should be unchanged
      expect(controller.getPixelSize('middle'), isNull);

      // Right (eager pixel) pane should have shrunk to absorb overflow
      // Overflow is 50px (100 - 50 max), right should shrink from 300 to 250
      expect(controller.getPixelSize('right'), 250);
    });

    test('reluctant panes absorb after eager panes exhausted', () {
      // Layout: [pixel:100] [eager:200, min:100] [reluctant:200, min:50]
      final controller = PaneController(
        entries: [
          PaneEntry(
            id: 'left',
            initialSize: PaneSize.pixel(100),
            maxSize: PaneSize.pixel(200),
            resizeBehavior: ResizeBehavior.eager,
          ),
          PaneEntry(
            id: 'middle',
            initialSize: PaneSize.pixel(200),
            minSize: PaneSize.pixel(100),
            resizeBehavior: ResizeBehavior.eager,
          ),
          PaneEntry(
            id: 'right',
            initialSize: PaneSize.pixel(200),
            minSize: PaneSize.pixel(50),
            resizeBehavior: ResizeBehavior.reluctant,
          ),
        ],
      );

      // Resize left pane by 300 (way past max of 200)
      // Overflow of 200 should cascade
      // Middle (eager) can shrink from 200 to 100 (absorbs 100)
      // Right (reluctant) should then absorb remaining 100
      controller.resize(
        paneId: 'left',
        delta: 300,
        containerSize: containerSize,
        resizerThickness: resizerThickness,
      );

      // Left at max
      expect(controller.getPixelSize('left'), 200);

      // Middle should be at min
      expect(controller.getPixelSize('middle'), 100);

      // Right should have absorbed some delta
      final rightSize = controller.getPixelSize('right');
      expect(rightSize, isNotNull);
      expect(rightSize!, lessThan(200));
    });

    test('cascade stops at constraints', () {
      // All panes have constraints - cascade should stop when all exhausted
      final controller = PaneController(
        entries: [
          PaneEntry(
            id: 'left',
            initialSize: PaneSize.pixel(100),
            maxSize: PaneSize.pixel(150),
            resizeBehavior: ResizeBehavior.eager,
          ),
          PaneEntry(
            id: 'right',
            initialSize: PaneSize.pixel(100),
            minSize: PaneSize.pixel(80),
            resizeBehavior: ResizeBehavior.eager,
          ),
        ],
      );

      // Resize left past max - only 20 can cascade (right can go from 100 to 80)
      controller.resize(
        paneId: 'left',
        delta: 100,
        containerSize: containerSize,
        resizerThickness: resizerThickness,
      );

      expect(controller.getPixelSize('left'), 150);
      expect(controller.getPixelSize('right'), 80);
    });

    test('negative delta cascades correctly', () {
      // Resizing to shrink should cascade in opposite direction
      final controller = PaneController(
        entries: [
          PaneEntry(
            id: 'left',
            initialSize: PaneSize.pixel(100),
            maxSize: PaneSize.pixel(200),
            resizeBehavior: ResizeBehavior.eager,
          ),
          PaneEntry(
            id: 'right',
            initialSize: PaneSize.pixel(100),
            minSize: PaneSize.pixel(50),
            resizeBehavior: ResizeBehavior.eager,
          ),
        ],
      );

      // Resize right pane to shrink by a lot
      controller.resize(
        paneId: 'right',
        delta: -100,
        containerSize: containerSize,
        resizerThickness: resizerThickness,
        resizerIndex: 0, // Resizer between left and right
      );

      // Right should be at min
      expect(controller.getPixelSize('right'), 50);
    });

    test('fractional panes keep original fractions during cascade', () {
      // Layout: [pixel:200, max:300] [fraction:1.0] [fraction:1.0]
      // Fractional panes don't get explicit sizes during cascade.
      // They naturally shrink via the flex layout when flexSpace decreases.
      final controller = PaneController(
        entries: [
          PaneEntry(
            id: 'left',
            initialSize: PaneSize.pixel(200),
            maxSize: PaneSize.pixel(300),
            resizeBehavior: ResizeBehavior.eager,
          ),
          PaneEntry(
            id: 'middle',
            initialSize: PaneSize.fraction(1.0),
            minSize: PaneSize.pixel(100),
          ),
          PaneEntry(
            id: 'right',
            initialSize: PaneSize.fraction(1.0),
            minSize: PaneSize.pixel(100),
          ),
        ],
      );

      // Both should be null initially
      expect(controller.getFractionalSize('middle'), isNull);
      expect(controller.getFractionalSize('right'), isNull);

      // Resize left pane way past its max
      controller.resize(
        paneId: 'left',
        delta: 200,
        containerSize: containerSize,
        resizerThickness: resizerThickness,
      );

      // Left should be at max
      expect(controller.getPixelSize('left'), 300);

      // Fractional panes should STILL be null (no explicit override)
      // The flex layout handles the redistribution automatically
      expect(controller.getFractionalSize('middle'), isNull);
      expect(controller.getFractionalSize('right'), isNull);
    });

    test('fractional panes can be resized after cascade', () {
      // This tests that fractional panes remain resizable after cascade
      final controller = PaneController(
        entries: [
          PaneEntry(
            id: 'trigger',
            initialSize: PaneSize.pixel(100),
            maxSize: PaneSize.pixel(150),
            resizeBehavior: ResizeBehavior.eager,
          ),
          PaneEntry(
            id: 'flex1',
            initialSize: PaneSize.fraction(1.0),
            minSize: PaneSize.pixel(50),
          ),
          PaneEntry(
            id: 'flex2',
            initialSize: PaneSize.fraction(1.0),
            minSize: PaneSize.pixel(50),
          ),
        ],
      );

      // First, trigger cascade
      controller.resize(
        paneId: 'trigger',
        delta: 100,
        containerSize: 500,
        resizerThickness: 4,
      );

      // Fractions should still be null (not locked)
      expect(controller.getFractionalSize('flex1'), isNull);
      expect(controller.getFractionalSize('flex2'), isNull);

      // Now resize between the fractional panes
      controller.resize(
        paneId: 'flex1',
        delta: 50,
        containerSize: 500,
        resizerThickness: 4,
        adjacentPaneId: 'flex2',
      );

      // Now they should have explicit fractional sizes
      expect(controller.getFractionalSize('flex1'), isNotNull);
      expect(controller.getFractionalSize('flex2'), isNotNull);

      // flex1 should have grown, flex2 should have shrunk
      expect(controller.getFractionalSize('flex1')!, greaterThan(1.0));
      expect(controller.getFractionalSize('flex2')!, lessThan(1.0));
    });
  });

  group('Backward compatibility', () {
    test('existing resize behavior unchanged for single pixel pane', () {
      final controller = PaneController(
        entries: [
          PaneEntry(
            id: 'left',
            initialSize: PaneSize.pixel(100),
            minSize: PaneSize.pixel(50),
            maxSize: PaneSize.pixel(200),
          ),
          PaneEntry(
            id: 'right',
            initialSize: PaneSize.fraction(1.0),
          ),
        ],
      );

      controller.resize(
        paneId: 'left',
        delta: 50,
        containerSize: 500,
        resizerThickness: 4,
      );

      expect(controller.getPixelSize('left'), 150);
      // Right pane (fractional) should not have pixel size set
      expect(controller.getPixelSize('right'), isNull);
    });

    test('existing resize behavior unchanged for fractional panes', () {
      final controller = PaneController(
        entries: [
          PaneEntry(
            id: 'left',
            initialSize: PaneSize.fraction(1.0),
          ),
          PaneEntry(
            id: 'right',
            initialSize: PaneSize.fraction(1.0),
          ),
        ],
      );

      controller.resize(
        paneId: 'left',
        delta: 50,
        containerSize: 500,
        resizerThickness: 4,
        adjacentPaneId: 'right',
      );

      // Both should have fractional sizes updated
      expect(controller.getFractionalSize('left'), isNotNull);
      expect(controller.getFractionalSize('right'), isNotNull);
    });

    test('pixel panes default to fixed (no cascade)', () {
      // Default pixel panes should NOT cascade
      final controller = PaneController(
        entries: [
          PaneEntry(
            id: 'left',
            initialSize: PaneSize.pixel(100),
            maxSize: PaneSize.pixel(150),
          ),
          PaneEntry(
            id: 'right',
            initialSize: PaneSize.pixel(100),
          ),
        ],
      );

      // Even resizing past max shouldn't affect right (fixed by default)
      controller.resize(
        paneId: 'left',
        delta: 100,
        containerSize: 500,
        resizerThickness: 4,
      );

      expect(controller.getPixelSize('left'), 150);
      // Right pane should be unchanged (fixed by default)
      expect(controller.getPixelSize('right'), isNull);
    });
  });
}
