// client/test/widgets/compose/compose_paste_clip_bar_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/services/compose/compose_clip.dart';
import 'package:teampilot/widgets/compose/compose_paste_clip_bar.dart';

void main() {
  testWidgets('shows pasted label with line count and fires callbacks', (
    tester,
  ) async {
    final clip = ComposeClip()..setPasted('a\nb\nc');
    var editFired = false;
    var removeFired = false;
    addTearDown(clip.dispose);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ComposePasteClipBar(
            clip: clip,
            onEdit: () => editFired = true,
            onRemove: () => removeFired = true,
          ),
        ),
      ),
    );

    // "Pasted text · 3 lines" — the · separator makes exact text fragile.
    expect(find.textContaining('Pasted text'), findsOneWidget);
    expect(find.textContaining('3 lines'), findsOneWidget);

    await tester.tap(find.textContaining('Pasted text'));
    expect(editFired, isTrue);

    await tester.tap(find.byIcon(Icons.close_rounded));
    expect(removeFired, isTrue);
  });
}
