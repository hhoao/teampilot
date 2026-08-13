// client/test/widgets/compose/compose_paste_editor_dialog_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/services/compose/compose_clip.dart';
import 'package:teampilot/widgets/compose/compose_paste_editor_dialog.dart';

void main() {
  Future<void> pumpEditor(
    WidgetTester tester,
    ComposeClip clip,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => showComposePasteEditor(context, clip),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('Done commits edits and stays collapsed', (tester) async {
    final clip = ComposeClip()..setPasted('a\nb\nc');
    addTearDown(clip.dispose);

    await pumpEditor(tester, clip);
    expect(find.textContaining('3 lines'), findsOneWidget); // title

    await tester.enterText(find.byType(TextField), 'new\ncontent\nmore');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(clip.text, 'new\ncontent\nmore');
    expect(clip.collapsed, isTrue);
  });

  testWidgets('Cancel discards edits', (tester) async {
    final clip = ComposeClip()..setPasted('original');
    addTearDown(clip.dispose);

    await pumpEditor(tester, clip);
    await tester.enterText(find.byType(TextField), 'changed');
    await tester.tap(find.byIcon(Icons.close_rounded)); // leading close = cancel
    await tester.pumpAndSettle();

    expect(clip.text, 'original');
  });

  testWidgets('Remove clears the clip', (tester) async {
    final clip = ComposeClip()..setPasted('original');
    addTearDown(clip.dispose);

    await pumpEditor(tester, clip);
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(clip.collapsed, isFalse);
  });
}
