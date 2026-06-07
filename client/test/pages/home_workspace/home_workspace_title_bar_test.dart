import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/home_workspace/home_workspace_title_bar.dart';

void main() {
  testWidgets('title bar renders personal and team tabs', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const HomeWorkspaceTitleBar(
          tabs: [
            HomeProjectTab(
              id: 'personal',
              name: 'Solo',
              kind: HomeProjectTabKind.personal,
            ),
            HomeProjectTab(
              id: 'team',
              name: 'Shared',
              kind: HomeProjectTabKind.team,
            ),
          ],
          activeProjectId: 'personal',
        ),
      ),
    );

    expect(find.text('Solo'), findsOneWidget);
    expect(find.text('Shared'), findsOneWidget);
    expect(find.byType(HomeWorkspaceTitleBar), findsOneWidget);
  });
}
