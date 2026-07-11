import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
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

    testWidgets('filters unmatched options out of the list tree', (
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

      final search = find.byType(AppDropdownSearchField);
      await tester.enterText(search, 'bet');
      await tester.pump();

      // Lazy filter — non-matches are not retained as list rows.
      expect(find.text('beta'), findsOneWidget);
      expect(find.text('gamma'), findsNothing);
      expect(
        find.descendant(
          of: find.byType(ListView),
          matching: find.text('alpha'),
        ),
        findsNothing,
      );
      // Search field keeps focus across filter rebuilds.
      expect(
        tester.widget<AppDropdownSearchField>(search).focusNode.hasFocus,
        isTrue,
      );
    });

    testWidgets('keeps search focus while typing filters', (tester) async {
      await tester.pumpWidget(
        _wrap(
          AppDropdownField<String>(
            items: List.generate(40, (i) => 'item-$i'),
            searchable: true,
            searchMinItems: 0,
            itemLabel: (item) => item,
            onChanged: (_) {},
          ),
        ),
      );

      await tester.tap(find.byType(AppDropdownField<String>));
      await tester.pumpAndSettle();

      final search = find.byType(AppDropdownSearchField);
      await tester.enterText(search, 'item-1');
      await tester.pump();
      await tester.enterText(search, 'item-12');
      await tester.pump();

      expect(
        tester.widget<AppDropdownSearchField>(search).focusNode.hasFocus,
        isTrue,
      );
      expect(
        find.descendant(
          of: find.byType(ListView),
          matching: find.text('item-12'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(ListView),
          matching: find.text('item-13'),
        ),
        findsNothing,
      );
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

    testWidgets('onHighlightChanged tracks hover and clears on close', (
      tester,
    ) async {
      final highlights = <String?>[];
      await tester.pumpWidget(
        _wrap(
          AppDropdownField<String>(
            items: const ['alpha', 'beta'],
            searchable: false,
            itemLabel: (item) => item,
            onChanged: (_) {},
            onHighlightChanged: highlights.add,
          ),
        ),
      );

      await tester.tap(find.byType(AppDropdownField<String>));
      await tester.pumpAndSettle();

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(find.text('beta')));
      await tester.pumpAndSettle();

      expect(highlights, contains('beta'));

      await tester.tap(find.text('alpha'));
      await tester.pumpAndSettle();

      expect(highlights.last, isNull);
    });
  });

  group('AppDropdownField plain list height', () {
    testWidgets('short menus shrink to content instead of default overlay height', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          AppDropdownField<String>(
            items: const ['adaptive', 'classicDark', 'highContrast'],
            initialItem: 'adaptive',
            itemLabel: (item) => item,
            onChanged: (_) {},
          ),
        ),
      );

      await tester.tap(find.byType(AppDropdownField<String>));
      await tester.pumpAndSettle();

      final list = tester.widget<ListView>(find.byType(ListView));
      expect(list.shrinkWrap, isTrue);

      final listSize = tester.getSize(find.byType(ListView));
      expect(
        listSize.height,
        lessThan(kAppDropdownDefaultOverlayHeight),
        reason:
            '3-option menus must not expand to the 260px overlay max '
            '(leaves empty space under the last row)',
      );
    });
  });
}
