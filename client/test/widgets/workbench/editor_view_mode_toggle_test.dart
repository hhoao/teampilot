import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/widgets/workbench/editor_view_mode_toggle.dart';

Widget host({required bool editSelected}) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: Center(
      child: EditorViewModeToggle(
        editSelected: editSelected,
        previewSelected: !editSelected,
        onEditTap: () {},
        onPreviewTap: () {},
      ),
    ),
  ),
);

void main() {
  testWidgets('shows both segments with tooltips', (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await tester.pumpWidget(host(editSelected: false));
    expect(find.byTooltip(l10n.htmlViewToggleEdit), findsOneWidget);
    expect(find.byTooltip(l10n.htmlViewTogglePreview), findsOneWidget);
  });

  testWidgets('taps fire the matching callback', (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    var editTaps = 0;
    var previewTaps = 0;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: EditorViewModeToggle(
              editSelected: true,
              previewSelected: false,
              onEditTap: () => editTaps++,
              onPreviewTap: () => previewTaps++,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip(l10n.htmlViewToggleEdit));
    await tester.tap(find.byTooltip(l10n.htmlViewTogglePreview));
    expect(editTaps, 1);
    expect(previewTaps, 1);
  });
}
