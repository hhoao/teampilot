import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/widgets/dropdown/app_dropdown_field.dart';
import 'package:teampilot/widgets/dropdown/app_dropdown_search_field.dart';

import '../../support/post_frame_test_harness.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );
}

void main() {
  setUpTestAppStorage();
  tearDown(tearDownTestAppStorage);

  group('AppDropdownField searchable', () {
    testWidgets('filters options by label', (tester) async {
      String? selected;
      await tester.pumpWidget(
        _wrap(
          AppDropdownField<String>(
            items: const ['alpha', 'beta', 'gamma'],
            initialItem: 'alpha',
            searchable: true,
            searchMinItems: 0,
            itemLabel: (item) => item,
            onChanged: (value) => selected = value,
          ),
        ),
      );

      await tester.tap(find.byType(AppDropdownField<String>));
      await tester.pumpAndSettle();

      expect(find.byType(AppDropdownSearchField), findsOneWidget);
      expect(find.text('beta'), findsOneWidget);
      expect(find.text('gamma'), findsOneWidget);

      await tester.enterText(find.byType(AppDropdownSearchField), 'bet');
      await tester.pump();

      expect(find.text('beta'), findsOneWidget);
      expect(find.text('gamma'), findsNothing);
      expect(
        find.descendant(
          of: find.byType(ListView),
          matching: find.text('alpha'),
        ),
        findsNothing,
      );

      await tester.tap(find.text('beta'));
      await tester.pumpAndSettle();

      expect(selected, 'beta');
      expect(find.byType(AppDropdownSearchField), findsNothing);
    });

    testWidgets('shows empty state when nothing matches', (tester) async {
      await tester.pumpWidget(
        _wrap(
          AppDropdownField<String>(
            items: const ['alpha', 'beta'],
            searchable: true,
            searchMinItems: 0,
            emptySearchText: 'Nothing here',
            itemLabel: (item) => item,
            onChanged: (_) {},
          ),
        ),
      );

      await tester.tap(find.byType(AppDropdownField<String>));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(AppDropdownSearchField), 'zzz');
      await tester.pump();

      expect(find.text('Nothing here'), findsOneWidget);
      expect(find.text('alpha'), findsNothing);
      expect(find.text('beta'), findsNothing);
    });

    testWidgets('notifies onSearchChanged and clears on close', (tester) async {
      final queries = <String>[];
      await tester.pumpWidget(
        _wrap(
          AppDropdownField<String>(
            items: const ['alpha', 'beta'],
            searchable: true,
            searchMinItems: 0,
            itemLabel: (item) => item,
            onSearchChanged: queries.add,
            onChanged: (_) {},
          ),
        ),
      );

      await tester.tap(find.byType(AppDropdownField<String>));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(AppDropdownSearchField), 'a');
      await tester.pump();
      expect(queries, ['a']);

      await tester.tap(find.text('alpha'));
      await tester.pumpAndSettle();

      expect(queries.last, '');
    });

    testWidgets('keeps offstage options in the tree while filtering', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          AppDropdownField<String>(
            items: const ['alpha', 'beta', 'gamma'],
            searchable: true,
            searchMinItems: 0,
            itemLabel: (item) => item,
            onChanged: (_) {},
          ),
        ),
      );

      await tester.tap(find.byType(AppDropdownField<String>));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(AppDropdownSearchField), 'bet');
      await tester.pump();

      expect(find.byType(Offstage), findsNWidgets(3));
      expect(find.text('beta'), findsOneWidget);
      expect(find.text('gamma'), findsNothing);
    });

    testWidgets('hides search below searchMinItems threshold', (tester) async {
      await tester.pumpWidget(
        _wrap(
          AppDropdownField<String>(
            items: const ['one', 'two'],
            searchable: true,
            searchMinItems: 3,
            itemLabel: (item) => item,
            onChanged: (_) {},
          ),
        ),
      );

      await tester.tap(find.byType(AppDropdownField<String>));
      await tester.pumpAndSettle();

      expect(find.byType(AppDropdownSearchField), findsNothing);
      expect(find.text('one'), findsOneWidget);
      expect(find.text('two'), findsOneWidget);
    });
  });
}
