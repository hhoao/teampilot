import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/widgets/settings/workspace_hub_shell.dart';
import 'package:teampilot/widgets/settings/workspace_section_host.dart';

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
}
