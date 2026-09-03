import 'package:flutter/gestures.dart' show kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/git_graph/git_graph_column_header.dart';
import 'package:teampilot/pages/git_graph/git_graph_columns.dart';

Widget _host({required VoidCallback onHide}) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('en'),
  home: Scaffold(
    body: GitGraphColumnHeader(
      graphWidth: GitGraphColumns.graphWidthFor(maxLane: 0),
      onHide: onHide,
    ),
  ),
);

void main() {
  testWidgets('renders five column labels', (tester) async {
    await tester.pumpWidget(_host(onHide: () {}));
    await tester.pumpAndSettle();

    expect(find.text('Graph'), findsOneWidget);
    expect(find.text('Description'), findsOneWidget);
    expect(find.text('Date'), findsOneWidget);
    expect(find.text('Author'), findsOneWidget);
    expect(find.text('Commit'), findsOneWidget);
  });

  testWidgets('secondary tap can hide via callback', (tester) async {
    var hidden = false;
    await tester.pumpWidget(_host(onHide: () => hidden = true));
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(GitGraphColumnHeader)),
      buttons: kSecondaryMouseButton,
    );
    await gesture.up();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Hide column header'));
    await tester.pumpAndSettle();

    expect(hidden, isTrue);
  });
}
