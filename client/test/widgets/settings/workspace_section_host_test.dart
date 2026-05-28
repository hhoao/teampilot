import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/widgets/settings/workspace_hub_shell.dart';
import 'package:teampilot/widgets/settings/workspace_section_host.dart';
import 'package:teampilot/widgets/settings/workspace_section_navigation.dart';

enum _TestSection { alpha, beta }

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
  Widget wrap(Widget child) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SizedBox(width: 900, height: 600, child: child)),
    );
  }

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
    expect(find.text('Manage skills'), findsOneWidget);
    expect(find.text('Nav'), findsOneWidget);
    expect(find.text('Body'), findsOneWidget);
    expect(find.byType(WorkspaceSplitShell), findsOneWidget);
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
}
