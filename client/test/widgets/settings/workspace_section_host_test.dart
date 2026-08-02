import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/layout_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/widgets/split_layout.dart';
import 'package:teampilot/widgets/settings/workspace_hub_shell.dart';
import 'package:teampilot/widgets/settings/workspace_pane_insets.dart';
import 'package:teampilot/services/workspace/workspace_pane_policy.dart';
import 'package:teampilot/widgets/settings/workspace_section_host.dart';
import 'package:teampilot/widgets/settings/workspace_section_nav_item.dart';
import 'package:teampilot/widgets/settings/workspace_section_navigation.dart';
import 'package:teampilot/widgets/settings/workspace_section_tab_bar.dart';

enum _TestSection { alpha, beta }

void _noop() {}

const _hubEntries = [
  WorkspaceHubEntry(
    title: 'Section',
    icon: Icons.star_outline,
    onTap: _noop,
  ),
];

class _TestSectionDescriptor implements WorkspaceSectionDescriptor {
  _TestSectionDescriptor(this.section);

  final _TestSection section;

  @override
  String get routeSegment => section.name;

  @override
  String routePath(String basePath) => '$basePath/${section.name}';

  @override
  String title(AppLocalizations l10n) => section.name;

  @override
  IconData get icon => Icons.star_outline;
}

void main() {
  Widget wrap(
    Widget child, {
    double width = 900,
    double height = 600,
  }) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: BlocProvider(
        create: (_) => LayoutCubit(),
        child: Scaffold(
          body: SizedBox(width: width, height: height, child: child),
        ),
      ),
    );
  }

  const compactItems = [
    WorkspaceSectionNavItem(
      label: 'Installed',
      selected: true,
      onSelect: _noop,
    ),
    WorkspaceSectionNavItem(
      label: 'Discovery',
      selected: false,
      onSelect: _noop,
    ),
  ];

  testWidgets('desktop shell shows title bar and split body', (tester) async {
    await tester.pumpWidget(
      wrap(
        const WorkspaceHubDesktopShell(
          title: 'Skills',
          subtitle: 'Manage skills',
          nav: SizedBox(child: Text('Nav')),
          body: Text('Body'),
        ),
      ),
    );
    expect(find.text('Skills'), findsOneWidget);
    expect(find.text('Manage skills'), findsNothing);
    expect(find.text('Nav'), findsOneWidget);
    expect(find.text('Body'), findsOneWidget);
    expect(find.byType(WorkspaceSplitShell), findsOneWidget);
    expect(find.byType(TwoPaneSplitView), findsOneWidget);
  });

  testWidgets('adaptive section page renders desktop shell on non-Android', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        WorkspaceAdaptiveSectionPage(
          pageKey: const Key('test-page'),
          title: 'Plugins',
          subtitle: 'Manage plugins',
          nav: const SizedBox(child: Text('Nav')),
          body: const Text('Body'),
        ),
      ),
    );
    expect(find.byType(WorkspaceSplitShell), findsOneWidget);
    expect(find.text('Plugins'), findsOneWidget);
  });

  testWidgets('adaptive section page forwards embedded to desktop shell', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        WorkspaceAdaptiveSectionPage(
          pageKey: const Key('test-page'),
          title: 'Plugins',
          subtitle: 'Manage plugins',
          nav: const SizedBox(child: Text('Nav')),
          body: const Text('Body'),
          embedded: true,
        ),
      ),
    );
    final shell = tester.widget<WorkspaceHubDesktopShell>(
      find.byType(WorkspaceHubDesktopShell),
    );
    expect(shell.embedded, isTrue);
  });

  testWidgets('desktop shell applies page inset when not embedded', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        const WorkspaceHubDesktopShell(
          title: 'Skills',
          subtitle: 'Manage skills',
          nav: SizedBox(child: Text('Nav')),
          body: Text('Body'),
        ),
      ),
    );
    final shell = tester.widget<WorkspaceHubDesktopShell>(
      find.byType(WorkspaceHubDesktopShell),
    );
    expect(shell.embedded, isFalse);

    final padding = tester.widget<Padding>(
      find.descendant(
        of: find.byType(WorkspaceHubDesktopShell),
        matching: find.byType(Padding),
      ).first,
    );
    expect(padding.padding, WorkspacePaneInsets.page);
  });

  testWidgets('desktop shell skips page inset when embedded', (tester) async {
    await tester.pumpWidget(
      wrap(
        const WorkspaceHubDesktopShell(
          title: 'Skills',
          subtitle: 'Manage skills',
          nav: SizedBox(child: Text('Nav')),
          body: Text('Body'),
          embedded: true,
        ),
      ),
    );
    final shell = tester.widget<WorkspaceHubDesktopShell>(
      find.byType(WorkspaceHubDesktopShell),
    );
    expect(shell.embedded, isTrue);

    final paddings = tester
        .widgetList<Padding>(
          find.descendant(
            of: find.byType(WorkspaceHubDesktopShell),
            matching: find.byType(Padding),
          ),
        )
        .toList();
    expect(
      paddings.any((p) => p.padding == WorkspacePaneInsets.page),
      isFalse,
    );
  });

  testWidgets('hub page shows title and hides subtitle by default', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        const WorkspaceHubPage(
          pageKey: Key('hub-page'),
          title: 'Skills',
          subtitle: 'Manage skills',
          entries: _hubEntries,
        ),
      ),
    );
    expect(find.text('Skills'), findsOneWidget);
    expect(find.text('Manage skills'), findsNothing);
    expect(find.text('Section'), findsOneWidget);
  });

  testWidgets('hub page applies page inset when not embedded', (tester) async {
    await tester.pumpWidget(
      wrap(
        const WorkspaceHubPage(
          pageKey: Key('hub-page'),
          title: 'Skills',
          subtitle: 'Manage skills',
          entries: _hubEntries,
        ),
      ),
    );
    final page = tester.widget<WorkspaceHubPage>(find.byType(WorkspaceHubPage));
    expect(page.embedded, isFalse);

    final padding = tester.widget<Padding>(
      find.descendant(
        of: find.byType(WorkspaceHubPage),
        matching: find.byType(Padding),
      ).first,
    );
    expect(padding.padding, WorkspacePaneInsets.page);
  });

  testWidgets('hub page skips page inset when embedded', (tester) async {
    await tester.pumpWidget(
      wrap(
        const WorkspaceHubPage(
          pageKey: Key('hub-page'),
          title: 'Skills',
          subtitle: 'Manage skills',
          entries: _hubEntries,
          embedded: true,
        ),
      ),
    );
    final page = tester.widget<WorkspaceHubPage>(find.byType(WorkspaceHubPage));
    expect(page.embedded, isTrue);

    final paddings = tester
        .widgetList<Padding>(
          find.descendant(
            of: find.byType(WorkspaceHubPage),
            matching: find.byType(Padding),
          ),
        )
        .toList();
    expect(
      paddings.any((p) => p.padding == WorkspacePaneInsets.page),
      isFalse,
    );
  });

  testWidgets('enum nav panel invokes onSelect when entry tapped', (
    tester,
  ) async {
    _TestSection? selected;
    await tester.pumpWidget(
      wrap(
        SizedBox(
          width: 240,
          height: 400,
          child: WorkspaceEnumNavPanel<_TestSection>(
            sections: _TestSection.values,
            current: _TestSection.beta,
            basePath: '/test',
            descriptor: (s) => _TestSectionDescriptor(s),
            onSelect: (s) => selected = s,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('alpha'));
    expect(selected, _TestSection.alpha);
  });

  testWidgets('compact tabs: narrow shows tab strip not split', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      wrap(
        WorkspaceAdaptiveSectionPage(
          pageKey: const Key('p'),
          title: 'Skills',
          compactSectionTabs: true,
          items: compactItems,
          body: const Text('Body'),
        ),
        width: 400,
        height: 800,
      ),
    );
    expect(find.byType(WorkspaceSplitShell), findsNothing);
    expect(find.text('Installed'), findsOneWidget);
    expect(find.text('Discovery'), findsOneWidget);
    expect(find.text('Body'), findsOneWidget);
  });

  testWidgets('compact tabs: wide still splits', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      wrap(
        WorkspaceAdaptiveSectionPage(
          pageKey: const Key('p'),
          title: 'Skills',
          compactSectionTabs: true,
          items: compactItems,
          body: const Text('Body'),
        ),
        width: 1200,
        height: 800,
      ),
    );
    expect(find.byType(WorkspaceSplitShell), findsOneWidget);
  });

  testWidgets('compact tabs: single item hides strip', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      wrap(
        WorkspaceAdaptiveSectionPage(
          pageKey: const Key('p'),
          title: 'Extensions',
          compactSectionTabs: true,
          items: const [
            WorkspaceSectionNavItem(
              label: 'Installed',
              selected: true,
              onSelect: _noop,
            ),
          ],
          body: const Text('Body'),
        ),
        width: 400,
        height: 800,
      ),
    );
    expect(find.byType(WorkspaceSectionTabBar), findsNothing);
    expect(find.text('Body'), findsOneWidget);
  });

  test(
    'legacy adaptive without compactSectionTabs uses android body-only branch',
    () {
      expect(
        workspaceAdaptiveSectionLayout(
          compactSectionTabs: false,
          androidHubNavigation: true,
          viewportWidth: 400,
        ),
        WorkspaceAdaptiveSectionLayout.androidBodyOnly,
      );
      expect(
        workspaceAdaptiveSectionLayout(
          compactSectionTabs: false,
          androidHubNavigation: true,
          viewportWidth: 1200,
        ),
        WorkspaceAdaptiveSectionLayout.androidBodyOnly,
      );
    },
  );

  test('compact tabs narrow uses compact branch even on android hub path', () {
    expect(
      workspaceAdaptiveSectionLayout(
        compactSectionTabs: true,
        androidHubNavigation: true,
        viewportWidth: WorkspacePanePolicy.narrowBreakpointWidth - 1,
      ),
      WorkspaceAdaptiveSectionLayout.compactTabs,
    );
  });

  testWidgets('composite nav panel with footer lays out and scrolls', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        SizedBox(
          width: 240,
          height: 320,
          child: WorkspaceCompositeNavPanel(
            primaryEntries: [
              for (var i = 0; i < 6; i++)
                WorkspaceHubEntry(
                  title: 'section $i',
                  icon: Icons.star_outline,
                  density: WorkspaceHubNavDensity.relaxed,
                  onTap: () {},
                ),
            ],
            trailingChildren: [
              for (var i = 0; i < 12; i++)
                WorkspaceHubNavItem(
                  title: 'member $i',
                  icon: Icons.person_outline,
                  density: WorkspaceHubNavDensity.subItem,
                  onTap: () {},
                ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('section 0'), findsOneWidget);
    expect(find.text('member 0'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('member 11'),
      48,
      scrollable: find.descendant(
        of: find.byType(WorkspaceCompositeNavPanel),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.text('section 0'), findsNothing);
    expect(find.text('member 11'), findsOneWidget);
  });
}
