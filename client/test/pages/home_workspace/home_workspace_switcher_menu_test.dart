import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/home_closed_workspace_entry.dart';
import 'package:teampilot/pages/home_workspace/home_workspace_switcher_menu.dart';
import 'package:teampilot/pages/home_workspace/home_workspace_title_bar.dart';

Widget _wrap(Widget child) {
  final theme = ThemeData(useMaterial3: true);
  return TpTheme(
    data: TpThemeData.fromColorScheme(theme.colorScheme, scale: 1.0),
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: theme,
      home: Scaffold(
        body: Center(child: child),
      ),
    ),
  );
}

void main() {
  test('homeWorkspaceSwitcherShouldShowOpenSection is false when empty', () {
    expect(homeWorkspaceSwitcherShouldShowOpenSection(const []), isFalse);
  });

  test('homeWorkspaceSwitcherShouldShowOpenSection is true when tabs exist', () {
    expect(
      homeWorkspaceSwitcherShouldShowOpenSection(const [
        HomeWorkspaceTab(id: 'a', name: 'A'),
      ]),
      isTrue,
    );
  });

  testWidgets('tap anchor opens menu with create and sections', (tester) async {
    await tester.pumpWidget(
      _wrap(
        HomeWorkspaceSwitcherMenu(
          openTabs: const [
            HomeWorkspaceTab(id: 'open-1', name: 'Open One'),
          ],
          activeTabKey: 'open-1',
          recentlyClosed: const [
            HomeClosedWorkspaceEntry(
              workspaceId: 'closed-1',
              displayName: 'Closed One',
              primaryPath: '/tmp/c',
            ),
          ],
          onCreate: () {},
          onSelectOpen: (_) {},
          onReopenClosed: (_) {},
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();

    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(find.text(l10n.newWorkspace), findsOneWidget);
    expect(find.text(l10n.homeWorkspaceOpenTabs), findsOneWidget);
    expect(find.text('Open One'), findsOneWidget);
    expect(find.text(l10n.homeWorkspaceRecentlyClosed), findsOneWidget);
    expect(find.text('Closed One'), findsOneWidget);
  });

  testWidgets('tap create invokes onCreate', (tester) async {
    var created = false;
    await tester.pumpWidget(
      _wrap(
        HomeWorkspaceSwitcherMenu(
          openTabs: const [],
          recentlyClosed: const [],
          onCreate: () => created = true,
          onSelectOpen: (_) {},
          onReopenClosed: (_) {},
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    final l10n = lookupAppLocalizations(const Locale('en'));
    await tester.tap(find.text(l10n.newWorkspace));
    await tester.pumpAndSettle();
    expect(created, isTrue);
  });

  testWidgets('tap open tab invokes onSelectOpen', (tester) async {
    String? selected;
    await tester.pumpWidget(
      _wrap(
        HomeWorkspaceSwitcherMenu(
          openTabs: const [
            HomeWorkspaceTab(id: 'open-1', name: 'Open One'),
          ],
          activeTabKey: 'open-1',
          recentlyClosed: const [],
          onCreate: () {},
          onSelectOpen: (id) => selected = id,
          onReopenClosed: (_) {},
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check), findsOneWidget);
    await tester.tap(find.text('Open One'));
    await tester.pumpAndSettle();
    expect(selected, 'open-1');
  });

  testWidgets('tap recently closed invokes onReopenClosed', (tester) async {
    String? reopened;
    await tester.pumpWidget(
      _wrap(
        HomeWorkspaceSwitcherMenu(
          openTabs: const [],
          recentlyClosed: const [
            HomeClosedWorkspaceEntry(
              workspaceId: 'closed-1',
              displayName: 'Closed One',
            ),
          ],
          onCreate: () {},
          onSelectOpen: (_) {},
          onReopenClosed: (key) => reopened = key,
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Closed One'));
    await tester.pumpAndSettle();
    expect(reopened, isNotNull);
  });

  testWidgets('omits open section when no open tabs', (tester) async {
    await tester.pumpWidget(
      _wrap(
        HomeWorkspaceSwitcherMenu(
          openTabs: const [],
          recentlyClosed: const [],
          onCreate: () {},
          onSelectOpen: (_) {},
          onReopenClosed: (_) {},
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(find.text(l10n.homeWorkspaceOpenTabs), findsNothing);
    expect(find.text(l10n.homeWorkspaceRecentlyClosedEmpty), findsOneWidget);
  });
}
