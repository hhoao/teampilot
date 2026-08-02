import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/theme/app_font_resolver.dart';
import 'package:teampilot/theme/app_markdown_style_sheet.dart';
import 'package:teampilot/theme/app_theme.dart';
import 'package:teampilot/theme/app_typography_scale.dart';
import 'package:teampilot/widgets/scroll_cursor_lock.dart';
import 'package:tp_markdown/tp_markdown.dart';

const _readmeFixture = '''
# TeamPilot

Intro paragraph.

## Acknowledgements

- File icons
''';

ThemeData _themeForTest() {
  final fonts = AppFontResolver.resolve(
    uiFontId: 'system',
    monoFontId: 'jetbrainsMono',
    platform: TargetPlatform.linux,
  );
  return buildLightTheme(null, AppTypographyScale.standard, null, fonts);
}

/// Mirrors [_MarkdownPreviewPane] layout without [EditorCubit] tree-sitter open.
Widget _previewPaneFixture(
  ThemeData theme,
  String markdown, {
  bool scrollCursorLockActive = false,
}) {
  return ScrollCursorLock(
    active: scrollCursorLockActive,
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: AiLineSpacedSelectionStyle(
        child: SelectionArea(
          child: MarkdownView(
            document: compileMarkdown(markdown),
            tokens: buildAppMarkdownTokens(theme, MarkdownProfile.document),
            resolvers: const MarkdownResolvers(),
          ),
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('markdown file preview renders MarkdownView', (
    tester,
  ) async {
    final theme = _themeForTest();
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: TpTheme(
          data: TpThemeData.fromColorScheme(theme.colorScheme, scale: 1.0),
          child: Scaffold(
            body: _previewPaneFixture(theme, _readmeFixture),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(MarkdownView), findsOneWidget);
    expect(find.byType(SelectionArea), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(find.byType(ScrollCursorLock), findsOneWidget);
    expect(
      tester.widget<ScrollCursorLock>(find.byType(ScrollCursorLock)).active,
      isFalse,
    );
  });

  testWidgets('markdown preview scroll cursor lock can force basic cursor', (
    tester,
  ) async {
    final theme = _themeForTest();
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: TpTheme(
          data: TpThemeData.fromColorScheme(theme.colorScheme, scale: 1.0),
          child: Scaffold(
            body: _previewPaneFixture(
              theme,
              _readmeFixture,
              scrollCursorLockActive: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      tester.widget<ScrollCursorLock>(find.byType(ScrollCursorLock)).active,
      isTrue,
    );
  });

  testWidgets('document vs compact profiles change headingTop SizedBox heights', (
    tester,
  ) async {
    final theme = _themeForTest();
    final document = buildAppMarkdownTokens(theme, MarkdownProfile.document);
    final compact = buildAppMarkdownTokens(theme, MarkdownProfile.compact);
    final fixture = compileMarkdown(_readmeFixture);

    Future<List<double>> headingTopHeights(MarkdownTokens tokens) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MarkdownView(document: fixture, tokens: tokens),
          ),
        ),
      );
      return tester
          .widgetList<SizedBox>(find.byType(SizedBox))
          .map((s) => s.height)
          .whereType<double>()
          .toList();
    }

    final documentHeights = await headingTopHeights(document);
    final compactHeights = await headingTopHeights(compact);

    expect(documentHeights, contains(document.h2TopSpacing));
    expect(compactHeights, contains(compact.h2TopSpacing));
    expect(document.h2TopSpacing, greaterThan(compact.h2TopSpacing));
    expect(documentHeights.length, compactHeights.length);
  });
}
