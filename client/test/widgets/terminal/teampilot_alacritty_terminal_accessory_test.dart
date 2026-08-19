import 'package:flutter/material.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/widgets/terminal/teampilot_terminal_accessory_host.dart';
import '../../support/rust_lib_test_init.dart';

void main() {
  setUpAll(initRustLibForTests);
  testWidgets('shows accessory bar when showAccessory true', (tester) async {
    final latch = ModifierLatch();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TeampilotTerminalAccessoryHost(
            showAccessory: true,
            latch: latch,
            viewKey: GlobalKey<TerminalViewState>(),
            child: const SizedBox(height: 100, width: 200),
          ),
        ),
      ),
    );

    expect(find.text('Ctrl'), findsOneWidget);
    expect(find.text('Esc'), findsOneWidget);
  });

  testWidgets('hides accessory bar when showAccessory false', (tester) async {
    final latch = ModifierLatch();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TeampilotTerminalAccessoryHost(
            showAccessory: false,
            latch: latch,
            viewKey: GlobalKey<TerminalViewState>(),
            child: const SizedBox(height: 100, width: 200),
          ),
        ),
      ),
    );

    expect(find.text('Ctrl'), findsNothing);
    expect(find.text('Esc'), findsNothing);
  });
}
