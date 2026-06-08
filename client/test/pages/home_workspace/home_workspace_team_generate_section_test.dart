import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/pages/home_workspace/home_workspace_team_generate_section.dart';

void main() {
  testWidgets('renders description field and generate button, no toggle',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: HomeWorkspaceTeamGenerateSection(
            cli: CliTool.claude,
            providerId: 'p',
            generating: false,
            onGenerate: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('team-gen-description')), findsOneWidget);
    expect(find.byKey(const ValueKey('team-gen-button')), findsOneWidget);
    expect(find.text('Members only'), findsNothing);
  });

  testWidgets('generate button reports the description', (tester) async {
    String? gotDescription;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: HomeWorkspaceTeamGenerateSection(
            cli: CliTool.claude,
            providerId: 'p',
            generating: false,
            onGenerate: (desc) => gotDescription = desc,
          ),
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('team-gen-description')),
      'My team',
    );
    await tester.tap(find.byKey(const ValueKey('team-gen-button')));
    await tester.pump();

    expect(gotDescription, 'My team');
  });
}
