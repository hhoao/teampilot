import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/shortcut_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/config/shortcuts_config_section.dart';
import 'package:teampilot/repositories/keybinding_repository.dart';

import '../../support/post_frame_test_harness.dart';

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  // KeybindingRepository does real file I/O, which only resolves inside
  // tester.runAsync() — TestWidgetsFlutterBinding doesn't pump the real
  // event loop that dart:io Futures depend on.
  Future<ShortcutCubit> loadedCubit(WidgetTester tester) async {
    final cubit = ShortcutCubit(repository: KeybindingRepository());
    await tester.runAsync(() => cubit.load());
    return cubit;
  }

  Future<void> pumpSection(WidgetTester tester, ShortcutCubit cubit) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: BlocProvider.value(
          value: cubit,
          child: const Scaffold(
            body: ShortcutsConfigWorkspace(showHeading: true),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('renders category groups and command rows with default chords', (
    tester,
  ) async {
    final cubit = await loadedCubit(tester);
    addTearDown(cubit.close);

    await pumpSection(tester, cubit);

    expect(find.text('Navigation'), findsOneWidget);
    expect(find.text('Compose'), findsOneWidget);
    expect(find.text('Close Session Tab'), findsOneWidget);
    expect(find.text('Send Message'), findsOneWidget);
  });

  testWidgets('search filters rows by title', (tester) async {
    final cubit = await loadedCubit(tester);
    addTearDown(cubit.close);

    await pumpSection(tester, cubit);

    await tester.enterText(find.byType(TextField), 'zoom');
    await tester.pump();

    expect(find.text('Zoom In'), findsOneWidget);
    expect(find.text('Close Session Tab'), findsNothing);
  });

  testWidgets('unbinding a command shows "Not set"', (tester) async {
    final cubit = await loadedCubit(tester);
    addTearDown(cubit.close);
    await tester.runAsync(() => cubit.unbind('workbench.zoom.in'));

    await pumpSection(tester, cubit);
    await tester.enterText(find.byType(TextField), 'zoom in');
    await tester.pump();

    expect(find.text('Not set'), findsOneWidget);
  });
}
