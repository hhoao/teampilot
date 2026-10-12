import 'package:flutter/material.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/theme/app_typography_scale.dart';
import 'package:teampilot/widgets/terminal_find_bar.dart';
import 'package:teampilot/widgets/workspace_terminal/workspace_terminal_find_host.dart';

import '../../support/rust_lib_test_init.dart';

Widget _harness({
  required GlobalKey<WorkspaceTerminalFindHostState> key,
  required TerminalEngine engine,
  required TerminalController controller,
  required String activeEntryId,
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
        body: WorkspaceTerminalFindHost(
          key: key,
          engine: engine,
          controller: controller,
          activeEntryId: activeEntryId,
          child: const SizedBox.expand(child: Text('term')),
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(initRustLibForTests);

  late TerminalEngine engine;
  late TerminalController controller;
  final key = GlobalKey<WorkspaceTerminalFindHostState>();

  setUp(() {
    engine = TerminalEngine(config: TerminalConfig.defaults());
    controller = TerminalController()..attach(engine);
  });

  tearDown(() {
    controller.dispose();
    engine.dispose();
  });

  testWidgets('openFind shows TerminalFindBar', (tester) async {
    await tester.pumpWidget(
      _harness(
        key: key,
        engine: engine,
        controller: controller,
        activeEntryId: 'a',
      ),
    );
    expect(find.byType(TerminalFindBar), findsNothing);
    key.currentState!.openFind();
    await tester.pumpAndSettle();
    expect(find.byType(TerminalFindBar), findsOneWidget);
    expect(find.text('Find in terminal'), findsOneWidget);
  });

  testWidgets('close hides TerminalFindBar', (tester) async {
    await tester.pumpWidget(
      _harness(
        key: key,
        engine: engine,
        controller: controller,
        activeEntryId: 'a',
      ),
    );
    key.currentState!.openFind();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(TerminalFindBar), findsNothing);
  });

  testWidgets('changing activeEntryId hides the bar', (tester) async {
    await tester.pumpWidget(
      _harness(
        key: key,
        engine: engine,
        controller: controller,
        activeEntryId: 'a',
      ),
    );
    key.currentState!.openFind();
    await tester.pumpAndSettle();
    expect(find.byType(TerminalFindBar), findsOneWidget);

    await tester.pumpWidget(
      _harness(
        key: key,
        engine: engine,
        controller: controller,
        activeEntryId: 'b',
      ),
    );
    await tester.pump();
    expect(find.byType(TerminalFindBar), findsNothing);
  });

  testWidgets('swapping controller after the old one is disposed is safe', (
    tester,
  ) async {
    final other = TerminalController()..attach(engine);
    await tester.pumpWidget(
      _harness(
        key: key,
        engine: engine,
        controller: controller,
        activeEntryId: 'a',
      ),
    );
    key.currentState!.openFind();
    await tester.pumpAndSettle();
    controller.searchSet('x');

    final old = controller;
    controller = other;
    old.dispose();
    await tester.pumpWidget(
      _harness(key: key, engine: engine, controller: other, activeEntryId: 'b'),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(TerminalFindBar), findsNothing);
  });
}
