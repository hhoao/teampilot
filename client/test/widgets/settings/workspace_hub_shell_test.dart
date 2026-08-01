import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/theme/workspace_surface_layers.dart';
import 'package:teampilot/widgets/pane_entry_animation.dart';
import 'package:teampilot/widgets/split_layout.dart';
import 'package:teampilot/widgets/settings/workspace_hub_shell.dart';

void main() {
  testWidgets('section page paints workspacePage when not embedded', (
    tester,
  ) async {
    late ColorScheme cs;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            cs = Theme.of(context).colorScheme;
            return const Scaffold(
              body: WorkspaceSectionPage(
                pageKey: Key('section'),
                child: Text('Body'),
              ),
            );
          },
        ),
      ),
    );

    final outer = tester.widget<Container>(find.byKey(const Key('section')));
    expect(outer.color, cs.workspacePage);
  });

  testWidgets('section page is transparent when embedded in card chrome', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: WorkspaceSectionPage(
            pageKey: Key('section-embedded'),
            embedded: true,
            child: Text('Body'),
          ),
        ),
      ),
    );

    final outer = tester.widget<Container>(
      find.byKey(const Key('section-embedded')),
    );
    expect(outer.color, isNull);
  });

  testWidgets('hub page is transparent when embedded in card chrome', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: WorkspaceHubPage(
            pageKey: Key('hub-embedded'),
            title: 'MCP',
            embedded: true,
            entries: [],
          ),
        ),
      ),
    );

    final outer = tester.widget<Container>(
      find.byKey(const Key('hub-embedded')),
    );
    expect(outer.color, isNull);
  });

  testWidgets('hub page paints workspacePage when not embedded', (tester) async {
    late ColorScheme cs;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            cs = Theme.of(context).colorScheme;
            return const Scaffold(
              body: WorkspaceHubPage(
                pageKey: Key('hub-page'),
                title: 'MCP',
                entries: [],
              ),
            );
          },
        ),
      ),
    );

    final outer = tester.widget<Container>(find.byKey(const Key('hub-page')));
    expect(outer.color, cs.workspacePage);
  });

  testWidgets('split shell lays out nav and body', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 500,
            child: WorkspaceSplitShell(
              nav: const SizedBox(child: Text('Nav')),
              body: const Text('Body'),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(TwoPaneSplitView), findsOneWidget);
    expect(find.byType(PaneEntryAnimation), findsOneWidget);
    expect(find.text('Nav'), findsOneWidget);
    expect(find.text('Body'), findsOneWidget);
  });

  testWidgets('split shell animates when body key changes', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 500,
            child: WorkspaceSplitShell(
              nav: const SizedBox(child: Text('Nav')),
              body: const KeyedSubtree(
                key: ValueKey('a'),
                child: Text('Pane A'),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Pane A'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 500,
            child: WorkspaceSplitShell(
              nav: const SizedBox(child: Text('Nav')),
              body: const KeyedSubtree(
                key: ValueKey('b'),
                child: Text('Pane B'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));

    expect(find.text('Pane B'), findsOneWidget);
    expect(find.text('Pane A'), findsNothing);
  });

  testWidgets('nav list renders entries without entry animation', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 240,
            child: WorkspaceHubNavList(
              entries: [
                WorkspaceHubEntry(
                  key: const ValueKey('layout-entry'),
                  title: 'Layout',
                  icon: Icons.dashboard_customize_outlined,
                  onTap: () {},
                ),
                WorkspaceHubEntry(
                  title: 'Models',
                  icon: Icons.memory_outlined,
                  onTap: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('layout-entry')), findsOneWidget);
    expect(find.text('Models'), findsOneWidget);
  });

  testWidgets('team-lead nav item uses distinct leading icon', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorkspaceHubNavItem(
            title: 'team-lead',
            icon: Icons.person_outline,
            showLeaderBadge: true,
            onTap: () {},
          ),
        ),
      ),
    );

    expect(find.byIcon(WorkspaceHubNavItem.teamLeadNavIcon), findsOneWidget);
    expect(find.byIcon(Icons.person_outline), findsNothing);
  });

  testWidgets('relaxed nav item uses taller tap target', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorkspaceHubNavItem(
            title: 'Team',
            icon: Icons.groups_outlined,
            density: WorkspaceHubNavDensity.relaxed,
            onTap: () {},
          ),
        ),
      ),
    );
    // Find the SizedBox with height 54 inside the nav item
    expect(
      find.byWidgetPredicate((w) => w is SizedBox && w.height == 54),
      findsOneWidget,
    );
  });
}
