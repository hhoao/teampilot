import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/skill.dart';
import 'package:teampilot/pages/skills/skill_detail_view.dart';

void main() {
  const skill = Skill(
    id: 'local:demo',
    name: 'demo-skill',
    description: 'd',
    directory: 'demo',
    installedAt: 1,
    updatedAt: 1,
  );

  Widget host(Widget child) {
    final theme = ThemeData(useMaterial3: true);
    return TpTheme(
      data: TpThemeData.fromColorScheme(theme.colorScheme, scale: 1.0),
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: theme,
        home: Scaffold(
          body: SizedBox(width: 480, height: 640, child: child),
        ),
      ),
    );
  }

  testWidgets('renders SKILL.md body and returns on back', (tester) async {
    var back = 0;
    await tester.pumpWidget(
      host(
        SkillDetailView(
          skill: skill,
          onBack: () => back++,
          loadMarkdown: (_) async => '# Hello skill\n\nDo the thing.',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('demo-skill'), findsOneWidget);
    expect(find.textContaining('Hello skill'), findsWidgets);
    expect(find.textContaining('Do the thing.'), findsWidgets);

    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pump();
    expect(back, 1);
  });

  testWidgets('shows empty copy when SKILL.md is missing', (tester) async {
    await tester.pumpWidget(
      host(
        SkillDetailView(
          skill: skill,
          onBack: () {},
          loadMarkdown: (_) async => null,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('No SKILL.md found for this skill.'),
      findsOneWidget,
    );
  });

  testWidgets('shows read-error copy when load throws', (tester) async {
    await tester.pumpWidget(
      host(
        SkillDetailView(
          skill: skill,
          onBack: () {},
          loadMarkdown: (_) async => throw StateError('io'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Could not read SKILL.md.'), findsOneWidget);
  });
}
