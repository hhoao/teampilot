import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/l10n_extensions.dart';
import 'package:teampilot/services/editor/html_view_mode_store.dart';
import 'package:teampilot/widgets/workbench/html_view_mode_toggle.dart';

void main() {
  testWidgets('tapping preview segment reports preview mode', (tester) async {
    HtmlViewMode? reported;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: HtmlViewModeToggle(
            mode: HtmlViewMode.edit,
            onModeChanged: (mode) => reported = mode,
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.visibility_outlined));
    expect(reported, HtmlViewMode.preview);

    await tester.tap(find.byIcon(Icons.code));
    expect(reported, HtmlViewMode.edit);
  });
}
