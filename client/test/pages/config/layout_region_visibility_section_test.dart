import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teampilot/cubits/layout_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/config/layout_region_visibility_section.dart';
import 'package:teampilot/repositories/layout_repository.dart';
import 'package:teampilot/utils/ui/app_keys.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('right tools switch defaults off and updates cubit', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final cubit = LayoutCubit(repository: LayoutRepository(prefs));
    addTearDown(cubit.close);
    await cubit.load();

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: SingleChildScrollView(
            child: BlocProvider.value(
              value: cubit,
              child: const LayoutRegionVisibilitySection(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final switchFinder = find.byKey(AppKeys.rightToolsVisibilitySwitch);
    expect(switchFinder, findsOneWidget);
    expect(tester.widget<Switch>(switchFinder).value, isFalse);
    expect(cubit.state.preferences.rightToolsVisible, isFalse);

    await tester.tap(switchFinder);
    await tester.pumpAndSettle();

    expect(tester.widget<Switch>(switchFinder).value, isTrue);
    expect(cubit.state.preferences.rightToolsVisible, isTrue);
  });

  testWidgets('session tab bar switch defaults on and updates cubit', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final cubit = LayoutCubit(repository: LayoutRepository(prefs));
    addTearDown(cubit.close);
    await cubit.load();

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: SingleChildScrollView(
            child: BlocProvider.value(
              value: cubit,
              child: const LayoutRegionVisibilitySection(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final switchFinder = find.byKey(AppKeys.sessionTabBarVisibilitySwitch);
    expect(switchFinder, findsOneWidget);
    expect(tester.widget<Switch>(switchFinder).value, isTrue);
    expect(cubit.state.preferences.sessionTabBarVisible, isTrue);

    await tester.tap(switchFinder);
    await tester.pumpAndSettle();

    expect(tester.widget<Switch>(switchFinder).value, isFalse);
    expect(cubit.state.preferences.sessionTabBarVisible, isFalse);
  });
}
