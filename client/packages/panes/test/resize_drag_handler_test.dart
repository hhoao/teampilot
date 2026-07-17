import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panes/src/resize_drag_handler.dart';

void main() {
  group('ResizeDragHandler', () {
    test('starts with zero cumulative delta', () {
      final handler = ResizeDragHandler(startSize: 200);
      expect(handler.cumulativeDelta, 0);
      expect(handler.requestedSize, 200);
    });

    test('accumulates positive deltas', () {
      final handler = ResizeDragHandler(startSize: 200);
      handler.addDelta(10);
      expect(handler.cumulativeDelta, 10);
      expect(handler.requestedSize, 210);

      handler.addDelta(15);
      expect(handler.cumulativeDelta, 25);
      expect(handler.requestedSize, 225);
    });

    test('accumulates negative deltas', () {
      final handler = ResizeDragHandler(startSize: 200);
      handler.addDelta(-30);
      expect(handler.cumulativeDelta, -30);
      expect(handler.requestedSize, 170);
    });

    test('handles direction changes', () {
      final handler = ResizeDragHandler(startSize: 200);

      // Drag right (grow)
      handler.addDelta(50);
      expect(handler.requestedSize, 250);

      // Reverse (shrink)
      handler.addDelta(-30);
      expect(handler.requestedSize, 220);

      // Continue shrinking
      handler.addDelta(-40);
      expect(handler.requestedSize, 180);
    });

    test('reset clears cumulative delta', () {
      final handler = ResizeDragHandler(startSize: 200);
      handler.addDelta(100);
      expect(handler.requestedSize, 300);

      handler.reset();
      expect(handler.cumulativeDelta, 0);
      expect(handler.requestedSize, 200);
    });

    test('simulates fast drag past max and back', () {
      final handler = ResizeDragHandler(startSize: 200);

      // Fast drag: +150px (past max of 300)
      handler.addDelta(150);
      expect(handler.requestedSize, 350);
      // Visual would clamp to 300, but handler tracks 350

      // Fast reverse: -100px
      handler.addDelta(-100);
      expect(handler.requestedSize, 250);
      // Now within bounds, visual should be 250

      // The key: requestedSize is always startSize + cumulativeDelta
      // No drift because we don't depend on visual position
      expect(handler.cumulativeDelta, 50); // 150 - 100
    });
  });

  group('GlobalDragTracker', () {
    test('calculates delta from last position', () {
      final tracker = GlobalDragTracker();
      tracker.onDragStart(const Offset(100, 50));

      // Move right by 20px
      var delta =
          tracker.calculateDelta(const Offset(120, 50), Axis.horizontal);
      expect(delta, 20);

      // Move right by another 15px
      delta = tracker.calculateDelta(const Offset(135, 50), Axis.horizontal);
      expect(delta, 15);

      // Move left by 10px
      delta = tracker.calculateDelta(const Offset(125, 50), Axis.horizontal);
      expect(delta, -10);
    });

    test('calculates total delta from start', () {
      final tracker = GlobalDragTracker();
      tracker.onDragStart(const Offset(100, 50));

      // Move to various positions, total should always be from start
      tracker.calculateDelta(const Offset(120, 50), Axis.horizontal);
      tracker.calculateDelta(const Offset(135, 50), Axis.horizontal);
      tracker.calculateDelta(const Offset(125, 50), Axis.horizontal);

      // Total delta from start (100) to current (125) = 25
      final total =
          tracker.calculateTotalDelta(const Offset(125, 50), Axis.horizontal);
      expect(total, 25);
    });

    test('vertical direction uses dy', () {
      final tracker = GlobalDragTracker();
      tracker.onDragStart(const Offset(100, 50));

      final delta =
          tracker.calculateDelta(const Offset(100, 80), Axis.vertical);
      expect(delta, 30);
    });

    test('isDragging tracks state', () {
      final tracker = GlobalDragTracker();
      expect(tracker.isDragging, false);

      tracker.onDragStart(const Offset(100, 50));
      expect(tracker.isDragging, true);

      tracker.onDragEnd();
      expect(tracker.isDragging, false);
    });

    test('handles rapid position updates without drift', () {
      final tracker = GlobalDragTracker();
      tracker.onDragStart(const Offset(100, 0));

      // Simulate rapid updates (like fast dragging)
      double totalDelta = 0;
      final positions = [110.0, 125.0, 145.0, 170.0, 160.0, 140.0, 130.0];

      for (final x in positions) {
        totalDelta += tracker.calculateDelta(Offset(x, 0), Axis.horizontal);
      }

      // Total from incremental deltas
      expect(totalDelta, 30); // 130 - 100

      // Total from start position (should match)
      final directTotal =
          tracker.calculateTotalDelta(const Offset(130, 0), Axis.horizontal);
      expect(directTotal, 30);
    });
  });

  group('Integration: Handler + Tracker', () {
    test('fast drag past max and back stays synchronized', () {
      final tracker = GlobalDragTracker();
      final handler = ResizeDragHandler(startSize: 200);

      tracker.onDragStart(const Offset(200, 0)); // Start at x=200

      // Fast drag right to x=350 (would be 150px past start)
      var delta = tracker.calculateDelta(const Offset(350, 0), Axis.horizontal);
      handler.addDelta(delta);
      expect(handler.requestedSize, 350); // 200 + 150

      // Visual would clamp to max (300), but handler has 350

      // Fast drag back left to x=270
      delta = tracker.calculateDelta(const Offset(270, 0), Axis.horizontal);
      handler.addDelta(delta);
      expect(handler.requestedSize, 270); // 200 + 70

      // Verify using total delta method
      final totalDelta =
          tracker.calculateTotalDelta(const Offset(270, 0), Axis.horizontal);
      expect(handler.startSize + totalDelta, 270);
    });

    test('demonstrates the drift problem with relative position', () {
      // This test shows what happens WITHOUT proper tracking
      // (simulating the old buggy behavior)

      double visualSize = 200;
      const maxSize = 300.0;

      // User drags +150px (past max)
      double requestedSize = visualSize + 150; // 350
      visualSize = requestedSize.clamp(0, maxSize); // Clamped to 300
      // Visual is now 300, but user's mouse moved 150px from 200

      // User reverses -80px
      // BUG: If we use visual position as base:
      double buggyRequestedSize = visualSize - 80; // 300 - 80 = 220
      // But user only moved 150 - 80 = 70px from start!
      // Correct size should be 200 + 70 = 270

      expect(buggyRequestedSize, 220); // Wrong!
      expect(200 + (150 - 80), 270); // Correct!
    });
  });
}
