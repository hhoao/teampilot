import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/floating_workspace/floating_panel_placement.dart';
import 'package:teampilot/pages/floating_workspace/floating_workspace_panel.dart';

void main() {
  test('defaultFloatingPanelBounds anchors bottom-right above toggle', () {
    final bounds = defaultFloatingPanelBounds(
      const Size(1400, 900),
      toggleOffset: const Offset(-24, -72),
    );
    expect(bounds.width, 720);
    expect(bounds.height, 480);
    expect(bounds.right, closeTo(1400 - 24, 0.1));
    // 72 toggle bottom + 36 toggle + 12 gap = 120
    expect(bounds.bottom, closeTo(900 - 120, 0.1));
    expect(bounds.left, greaterThan(400));
    expect(bounds.top, greaterThan(200));
  });

  test('placement stays relative when host size changes', () {
    const placement = FloatingPanelPlacement(
      width: 600,
      height: 400,
      rightInset: 40,
      bottomInset: 80,
    );
    final small = placement.resolve(const Size(1200, 800));
    final large = placement.resolve(const Size(1800, 1100));
    expect(small.right, closeTo(1200 - 40, 0.1));
    expect(small.bottom, closeTo(800 - 80, 0.1));
    expect(large.right, closeTo(1800 - 40, 0.1));
    expect(large.bottom, closeTo(1100 - 80, 0.1));
    // Same distance from the app's bottom-right corner.
    expect(large.right - large.left, small.right - small.left);
  });
}
