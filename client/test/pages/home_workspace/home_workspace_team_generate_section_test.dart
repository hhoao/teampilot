import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/home_workspace/home_workspace_team_generate_section.dart';

Widget _host({
  double? progress,
  required void Function(String) onDescriptionChanged,
}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: HomeTeamGenerateSection(
        progress: progress,
        onDescriptionChanged: onDescriptionChanged,
      ),
    ),
  );
}

void main() {
  testWidgets('reports the description as it changes; no progress bar idle',
      (tester) async {
    String? got;
    await tester.pumpWidget(_host(onDescriptionChanged: (v) => got = v));
    await tester.pump();

    expect(find.byKey(const ValueKey('team-gen-description')), findsOneWidget);
    expect(find.byKey(const ValueKey('team-gen-progress')), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('team-gen-description')),
      'My team',
    );
    expect(got, 'My team');
  });

  testWidgets('shows the progress bar while generating', (tester) async {
    await tester.pumpWidget(
      _host(progress: 0.4, onDescriptionChanged: (_) {}),
    );
    await tester.pump();

    final bar = tester.widget<LinearProgressIndicator>(
      find.byKey(const ValueKey('team-gen-progress')),
    );
    expect(bar.value, 0.4);
  });
}
