import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tp_markdown/tp_markdown.dart';

/// Edit chrome must reuse [MarkdownTokens] fingerprints (size/weight/
/// family). Ad-hoc `fontSize - 1` / bare `TextStyle(fontSize: 11)` miss host
/// glyph warmup and stall expand on Linux fontconfig.

/// Inline edit resolver: decodes the str_replace args shape the same way the
/// client's [StrReplaceEditHunkCodec] does, so the card mounts its diff body.
class _FingerprintEditResolver implements AiEditToolTargetResolver {
  const _FingerprintEditResolver();

  @override
  AiEditToolTarget? resolve(AiToolCallPart part) {
    final path = part.args?['file_path'] as String?;
    if (path == null) return null;
    final oldString = part.args?['old_string'] as String?;
    final newString = part.args?['new_string'] as String?;
    if (oldString == null && newString == null) return null;
    final startLine = part.args?['start_line'] as int?;
    final oldLines = (oldString ?? '').split('\n');
    final newLines = (newString ?? '').split('\n');
    var lineNumber = startLine;
    AiEditLine numbered(AiEditLineKind kind, String text) {
      final line = AiEditLine(kind: kind, text: text, lineNumber: lineNumber);
      if (lineNumber != null) {
        lineNumber = (lineNumber ?? 0) + 1;
      }
      return line;
    }

    final lines = <AiEditLine>[
      for (final text in oldLines) numbered(AiEditLineKind.remove, text),
      for (final text in newLines) numbered(AiEditLineKind.add, text),
    ];
    return AiEditToolTarget(
      hunk: AiEditHunk(
        path: path,
        lines: lines,
        addedCount: newLines.length,
        removedCount: oldLines.length,
        startLine: startLine,
      ),
    );
  }
}

class _FingerprintFileResolver implements AiToolFileTargetResolver {
  const _FingerprintFileResolver();

  @override
  AiToolFileTarget? resolve(AiToolCallPart part) => null;
}

class _FingerprintShellResolver implements AiShellToolTargetResolver {
  const _FingerprintShellResolver();

  @override
  AiShellToolTarget? resolve(AiToolCallPart part) => null;
}

void main() {
  testWidgets(
    'edit gutter/prefix/badge match markdown codeBlock/codeLanguage shape',
    (tester) async {
      final markdown = MarkdownTokens.test();
      final mono = markdown.codeBlock;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: [AiMessageTheme.test()]),
          home: AiToolFileActionsScope(
            actions: AiToolFileActions(
              fileResolver: const _FingerprintFileResolver(),
              editResolver: const _FingerprintEditResolver(),
              shellResolver: const _FingerprintShellResolver(),
            ),
            child: const Scaffold(
              body: AiToolCallPartView(
                part: AiToolCallPart(
                  toolCallId: '1',
                  toolName: 'StrReplace',
                  args: {
                    'file_path': 'lib/a.dart',
                    'old_string': 'final int x;',
                    'new_string': 'final int x;\nfinal int y;',
                    'start_line': 40,
                  },
                  result: 'ok',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final gutter = tester.widget<Text>(find.text('40'));
      expect(gutter.style?.fontFamily, mono.fontFamily);
      expect(gutter.style?.fontSize, mono.fontSize);
      expect(gutter.style?.fontWeight, mono.fontWeight);

      // Diff prefixes are single-character Text widgets inside the fade body.
      final prefixes = tester.widgetList<Text>(
        find.descendant(
          of: find.byType(AiFadeExpandBody),
          matching: find.byWidgetPredicate(
            (w) => w is Text && (w.data == '+' || w.data == '-'),
          ),
        ),
      );
      expect(prefixes, isNotEmpty);
      for (final prefix in prefixes) {
        expect(prefix.style?.fontFamily, mono.fontFamily);
        expect(prefix.style?.fontSize, mono.fontSize);
        expect(prefix.style?.fontWeight, mono.fontWeight);
      }

      final badgeStyle = markdown.codeLanguage.copyWith(
        color: const ColorScheme.light().primary,
        fontWeight: FontWeight.w600,
      );
      final badge = tester.widget<Text>(find.text('+2'));
      expect(badge.style?.fontFamily, badgeStyle.fontFamily);
      expect(badge.style?.fontSize, badgeStyle.fontSize);
      expect(badge.style?.fontWeight, badgeStyle.fontWeight);

      final removeBadge = tester.widget<Text>(find.text('-1'));
      expect(removeBadge.style?.fontSize, badgeStyle.fontSize);
      expect(removeBadge.style?.fontWeight, badgeStyle.fontWeight);
    },
  );
}
