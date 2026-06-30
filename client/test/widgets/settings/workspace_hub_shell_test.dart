import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/widgets/split_layout.dart';
import 'package:teampilot/widgets/settings/workspace_hub_shell.dart';

void main() {
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
    expect(find.text('Nav'), findsOneWidget);
    expect(find.text('Body'), findsOneWidget);
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

    expect(
      find.byIcon(WorkspaceHubNavItem.teamLeadNavIcon),
      findsOneWidget,
    );
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
