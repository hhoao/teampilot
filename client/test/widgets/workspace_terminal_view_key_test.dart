import 'package:flutter/material.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/widgets/workspace_terminal_panel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'stable GlobalKey<TerminalViewState> keeps the TerminalView element across '
    'an engine swap (no remount)',
    (tester) async {
      final engine1 = TerminalEngine(config: TerminalConfig.defaults());
      final engine2 = TerminalEngine(config: TerminalConfig.defaults());
      addTearDown(() {
        engine1.dispose();
        engine2.dispose();
      });

      final engineNotifier = ValueNotifier<TerminalEngine>(engine1);
      addTearDown(engineNotifier.dispose);

      final terminalKey = GlobalKey<TerminalViewState>(
        debugLabel: kWorkspaceTerminalViewDebugLabel,
      );

      // Mirror the panel's keying: a TerminalView under a shared GlobalKey,
      // swapping only the engine prop. With a per-entry key this would remount
      // and `identical(before, after)` would fail.
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<TerminalEngine>(
            valueListenable: engineNotifier,
            builder: (context, engine, _) => TerminalView(
              engine,
              key: terminalKey,
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      final before = tester.element(find.byType(TerminalView));
      engineNotifier.value = engine2;
      await tester.pump();
      final after = tester.element(find.byType(TerminalView));

      expect(
        identical(before, after),
        isTrue,
        reason: 'a stable key must reuse the TerminalView element on engine '
            'swap so the glyph cache stays warm (no partial-text flash)',
      );
    },
  );
}
