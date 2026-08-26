import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';
import 'package:teampilot/l10n/l10n_extensions.dart';
import 'package:teampilot/pages/workbench/markdown_preview_pane.dart';
import 'package:teampilot/services/editor/markdown_preview_find_controller.dart';
import 'package:teampilot/theme/app_markdown_style_sheet.dart';
import 'package:teampilot/widgets/workbench/markdown_preview_find_bar.dart';
import 'package:tp_markdown/tp_markdown.dart';

void main() {
  testWidgets('Mod+F opens bar; typing paints highlight; esc closes', (
    tester,
  ) async {
    final editing = CodeLineEditingController.fromText('# Hi\n\nfindme here\n');
    addTearDown(editing.dispose);
    final findController = MarkdownPreviewFindController();
    addTearDown(findController.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: MarkdownPreviewPane(
            controller: editing,
            resolvers: const MarkdownResolvers(),
            codeBlockMode: ContentDisplayMode.flatten,
            markdownPadding: const EdgeInsets.all(24),
            shellColor: Colors.white,
            findController: findController,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Key events propagate from the focused node up, so focus must live
    // *inside* the pane subtree for its Mod+F Shortcuts to see the chord —
    // tapping the preview text does what real usage does (SelectionArea grabs
    // focus on tap).
    await tester.tap(find.text('findme here'));
    await tester.pump();

    // Open via Mod+F shortcut
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(find.byType(MarkdownPreviewFindBar), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'findme');
    await tester.pump(const Duration(milliseconds: 250));

    final tokens = buildAppMarkdownTokens(
      Theme.of(tester.element(find.byType(Scaffold))),
      MarkdownProfile.document,
      width: 800,
    );
    // The first hit is also the active one, so both washes qualify.
    final washes = {
      tokens.matchHighlightColor,
      tokens.matchHighlightActiveColor,
    };
    bool washed(InlineSpan span) =>
        span is TextSpan &&
        (washes.contains(span.style?.backgroundColor) ||
            (span.children ?? const <InlineSpan>[]).any(washed));
    final highlighted = tester
        .widgetList<Text>(find.byType(Text))
        .any((text) => text.textSpan != null && washed(text.textSpan!));
    expect(highlighted, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byType(MarkdownPreviewFindBar), findsNothing);
  });
}
