import 'package:flutter/material.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/theme/app_typography_scale.dart';
import 'package:teampilot/widgets/workspace_terminal/workspace_terminal_context_menu.dart';

import '../../support/rust_lib_test_init.dart';

Widget _harness({
  required TerminalController controller,
  required TerminalEngine engine,
  required VoidCallback onFind,
  required VoidCallback onClear,
}) {
  final theme = ThemeData(useMaterial3: true);
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    theme: theme,
    home: TpTheme(
      data: TpThemeData.fromColorScheme(
        theme.colorScheme,
        scale: 1.0,
        controlScale: AppTypographyScale.standard.multiplier,
      ),
      child: Scaffold(
        body: Builder(
          builder: (context) {
            return Center(
              child: ElevatedButton(
                onPressed: () {
                  showWorkspaceTerminalContextMenu(
                    context: context,
                    menuContext: context,
                    terminalController: controller,
                    engine: engine,
                    globalPosition: const Offset(80, 80),
                    cellOffset: null,
                    onFindRequested: onFind,
                    onClearTerminal: onClear,
                    onOpenLink: (_) async {},
                    onAskAi: (_) async {},
                  );
                },
                child: const Text('open'),
              ),
            );
          },
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(initRustLibForTests);

  late TerminalEngine engine;
  late TerminalController controller;

  setUp(() {
    engine = TerminalEngine(config: TerminalConfig.defaults());
    controller = TerminalController()..attach(engine);
  });

  tearDown(() {
    controller.dispose();
    engine.dispose();
  });

  testWidgets('menu lists Find and Clear', (tester) async {
    await tester.pumpWidget(
      _harness(
        controller: controller,
        engine: engine,
        onFind: () {},
        onClear: () {},
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Find in terminal'), findsOneWidget);
    expect(find.text('Clear terminal'), findsOneWidget);
  });

  testWidgets('choosing Find calls onFindRequested', (tester) async {
    var findCalls = 0;
    await tester.pumpWidget(
      _harness(
        controller: controller,
        engine: engine,
        onFind: () => findCalls++,
        onClear: () {},
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Find in terminal'));
    await tester.pumpAndSettle();
    expect(findCalls, 1);
  });

  testWidgets('choosing Clear calls onClearTerminal', (tester) async {
    var clearCalls = 0;
    await tester.pumpWidget(
      _harness(
        controller: controller,
        engine: engine,
        onFind: () {},
        onClear: () => clearCalls++,
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear terminal'));
    await tester.pumpAndSettle();
    expect(clearCalls, 1);
  });
}
