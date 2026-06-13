import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/widgets/app_toggle_switch.dart';

void main() {
  group('computeToggleSegmentWidths', () {
    test('widens segments for longer labels and larger font', () {
      const labels = ['浅色', '深色', '跟随系统'];
      final small = computeToggleSegmentWidths(
        labels: labels,
        fontSize: 14,
        iconSize: 18,
        icons: const [
          Icons.light_mode_outlined,
          Icons.dark_mode_outlined,
          Icons.desktop_windows_outlined,
        ],
      );
      final large = computeToggleSegmentWidths(
        labels: labels,
        fontSize: 22,
        iconSize: 18,
        icons: const [
          Icons.light_mode_outlined,
          Icons.dark_mode_outlined,
          Icons.desktop_windows_outlined,
        ],
      );
      expect(large[2], greaterThan(small[2]));
      expect(large[2], greaterThan(132));
    });

    test('respects minSegmentWidth floor', () {
      final widths = computeToggleSegmentWidths(
        labels: const ['A'],
        fontSize: 12,
        iconSize: 16,
        minSegmentWidth: 120,
      );
      expect(widths.single, 120);
    });
  });

  testWidgets('shows full label text at large typography scale', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          textTheme: const TextTheme(bodyMedium: TextStyle(fontSize: 22)),
        ),
        home: Scaffold(
          body: Center(
            child: AppToggleSwitch(
              totalSwitches: 3,
              initialLabelIndex: 2,
              labels: const ['浅色', '深色', '跟随系统'],
              icons: const [
                Icons.light_mode_outlined,
                Icons.dark_mode_outlined,
                Icons.desktop_windows_outlined,
              ],
              onToggle: (_) {},
            ),
          ),
        ),
      ),
    );
    expect(find.text('跟随系统'), findsOneWidget);
  });
}
