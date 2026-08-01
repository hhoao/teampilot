import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/widgets/settings/workspace_pane_header.dart';

void main() {
  Widget wrap(Widget child) {
    final scheme = ColorScheme.fromSeed(seedColor: Colors.indigo);
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(colorScheme: scheme),
      home: TpTheme(
        data: TpThemeData.fromColorScheme(scheme, scale: 1),
        child: Scaffold(body: child),
      ),
    );
  }

  testWidgets('shows title and divider; hides subtitle by default', (tester) async {
    await tester.pumpWidget(
      wrap(
        const WorkspacePaneHeader(
          title: '全部工作区',
          subtitle: 'should stay hidden',
        ),
      ),
    );
    expect(find.text('全部工作区'), findsOneWidget);
    expect(find.text('should stay hidden'), findsNothing);
    expect(find.byType(Divider), findsOneWidget);
  });

  testWidgets('shows subtitle when showSubtitle is true', (tester) async {
    await tester.pumpWidget(
      wrap(
        const WorkspacePaneHeader(
          title: 'Skills',
          subtitle: 'Manage skills',
          showSubtitle: true,
        ),
      ),
    );
    expect(find.text('Manage skills'), findsOneWidget);
  });

  testWidgets('blank subtitle stays hidden even when showSubtitle is true', (tester) async {
    await tester.pumpWidget(
      wrap(
        const WorkspacePaneHeader(
          title: 'Skills',
          subtitle: '   ',
          showSubtitle: true,
        ),
      ),
    );
    expect(find.text('   '), findsNothing);
  });

  testWidgets('onBack shows leading control', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      wrap(
        WorkspacePaneHeader(
          title: 'Backable',
          onBack: () => tapped = true,
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    expect(tapped, isTrue);
  });
}
