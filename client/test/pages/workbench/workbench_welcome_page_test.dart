import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/shortcut_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/workbench/workbench_welcome_page.dart';
import 'package:teampilot/services/commands/command_bus.dart';
import 'package:teampilot/services/commands/command_ids.dart';
import 'package:teampilot/theme/app_theme.dart';
import 'package:teampilot/utils/ui/app_keys.dart';

import '../../support/post_frame_test_harness.dart';

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  Future<void> pumpWelcomePage(
    WidgetTester tester, {
    required CommandBus bus,
    required ShortcutCubit cubit,
  }) async {
    final theme = buildDarkTheme();
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: RepositoryProvider<CommandBus>.value(
          value: bus,
          child: BlocProvider<ShortcutCubit>.value(
            value: cubit,
            child: TpTheme(
              data: TpThemeData.fromColorScheme(
                theme.colorScheme,
                scale: 1,
              ),
              child: const Scaffold(body: WorkbenchWelcomePage()),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('tapping a row invokes CommandBus', (tester) async {
    final bus = CommandBus();
    final cubit = ShortcutCubit();
    addTearDown(cubit.close);
    var invoked = '';
    bus.register(
      CommandIds.togglePanel,
      () => invoked = CommandIds.togglePanel,
    );

    await pumpWelcomePage(tester, bus: bus, cubit: cubit);
    await tester.tap(
      find.byKey(
        AppKeys.workbenchWelcomeCommandRow(CommandIds.togglePanel),
      ),
    );
    await tester.pump();

    expect(invoked, CommandIds.togglePanel);
  });

  testWidgets('unbound command shows shortcutsNotSet and still invokes', (
    tester,
  ) async {
    final bus = CommandBus();
    final cubit = ShortcutCubit();
    addTearDown(cubit.close);
    var invoked = '';
    bus.register(
      CommandIds.showCheatsheet,
      () => invoked = CommandIds.showCheatsheet,
    );
    await tester.runAsync(() => cubit.unbind(CommandIds.showCheatsheet));

    await pumpWelcomePage(tester, bus: bus, cubit: cubit);

    expect(find.text('Not set'), findsOneWidget);
    await tester.tap(
      find.byKey(
        AppKeys.workbenchWelcomeCommandRow(CommandIds.showCheatsheet),
      ),
    );
    await tester.pump();
    expect(invoked, CommandIds.showCheatsheet);
  });
}
