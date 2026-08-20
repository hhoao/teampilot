import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/layout_cubit.dart';
import 'package:tp_markdown/tp_markdown.dart' show ContentDisplayMode;
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/config/layout_appearance_in_layout_section.dart';
import 'package:teampilot/repositories/layout_repository.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('content display mode selects render and bind to the cubit', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final cubit = LayoutCubit(repository: LayoutRepository(prefs));
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
              child: const LayoutAppearanceInLayoutSection(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Section + three mode selectors present, all defaulting to
    // foldFixedHeight ("Fold · fixed height" appears three times).
    expect(find.text('Content display'), findsOneWidget);
    expect(find.text('User messages'), findsOneWidget);
    expect(find.text('Code blocks in chat'), findsOneWidget);
    expect(find.text('Code blocks in file preview'), findsOneWidget);
    expect(find.byType(TpCompactSelect<ContentDisplayMode>), findsNWidgets(3));
    expect(find.text('Fold · fixed height'), findsNWidgets(3));
  });

  testWidgets('thinking-process fold section shows all category toggles', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final cubit = LayoutCubit(repository: LayoutRepository(prefs));
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
              child: const LayoutAppearanceInLayoutSection(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Fold into thinking process'), findsOneWidget);
    // 12 categories + the existing 2 cot expand switches + the auto-open
    // subagent preview switch = 15 Switch widgets.
    expect(find.byType(Switch), findsNWidgets(15));
    final switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
    // 7 workhorse categories default to folded (on); interaction categories
    // (subagent / ask user / plan / tasks & todos) and the two cot switches
    // plus auto-open subagent preview default off.
    final onCount = switches.where((s) => s.value).length;
    expect(onCount, 7);
  });
}
