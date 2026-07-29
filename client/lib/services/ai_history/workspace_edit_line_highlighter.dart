import 'dart:ui' show Brightness;

import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/painting.dart';

import '../editor_platform/editor_syntax_theme.dart';

/// Thin syntax highlighter for edit-card diff lines in History.
class WorkspaceAiEditLineHighlighter extends AiEditLineHighlighter {
  WorkspaceAiEditLineHighlighter({required Brightness brightness})
    : _theme = EditorSyntaxTheme.forBrightness(brightness);

  final EditorSyntaxTheme _theme;

  @override
  InlineSpan highlight({
    required String path,
    required String text,
    required AiEditLineKind kind,
    required TextStyle baseStyle,
  }) {
    try {
      return _highlightLine(
        extension: _extensionFor(path),
        text: text,
        baseStyle: baseStyle,
      );
    } on Object {
      return TextSpan(text: text, style: baseStyle);
    }
  }

  InlineSpan _highlightLine({
    required String? extension,
    required String text,
    required TextStyle baseStyle,
  }) {
    if (text.isEmpty) {
      return TextSpan(text: text, style: baseStyle);
    }

    final spans = <InlineSpan>[];
    final keywords = _keywordsFor(extension);
    var index = 0;

    while (index < text.length) {
      final comment = _matchComment(text, index, extension);
      if (comment != null) {
        spans.add(
          TextSpan(
            text: text.substring(index),
            style: _mergeStyle(baseStyle, _theme.styleFor('comment')),
          ),
        );
        break;
      }

      final string = _matchString(text, index);
      if (string != null) {
        spans.add(
          TextSpan(
            text: string,
            style: _mergeStyle(baseStyle, _theme.styleFor('string')),
          ),
        );
        index += string.length;
        continue;
      }

      final wordMatch = RegExp(r'[A-Za-z_]\w*').matchAsPrefix(text, index);
      if (wordMatch != null) {
        final word = wordMatch.group(0)!;
        final style = keywords.contains(word)
            ? _mergeStyle(baseStyle, _theme.styleFor('keyword'))
            : baseStyle;
        spans.add(TextSpan(text: word, style: style));
        index += word.length;
        continue;
      }

      final numberMatch = RegExp(r'\d+(?:\.\d+)?').matchAsPrefix(text, index);
      if (numberMatch != null) {
        spans.add(
          TextSpan(
            text: numberMatch.group(0),
            style: _mergeStyle(baseStyle, _theme.styleFor('number')),
          ),
        );
        index += numberMatch.end - numberMatch.start;
        continue;
      }

      spans.add(TextSpan(text: text[index], style: baseStyle));
      index++;
    }

    if (spans.isEmpty) {
      return TextSpan(text: text, style: baseStyle);
    }
    if (spans.length == 1 && spans.single is TextSpan) {
      final single = spans.single as TextSpan;
      if (single.children == null) return single;
    }
    return TextSpan(children: spans, style: baseStyle);
  }

  static String? _extensionFor(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return null;
    return path.substring(dot + 1).toLowerCase();
  }

  static Set<String> _keywordsFor(String? extension) {
    return switch (extension) {
      'dart' => const {
        'abstract',
        'as',
        'assert',
        'async',
        'await',
        'break',
        'case',
        'catch',
        'class',
        'const',
        'continue',
        'default',
        'do',
        'else',
        'enum',
        'export',
        'extends',
        'extension',
        'external',
        'factory',
        'false',
        'final',
        'finally',
        'for',
        'get',
        'if',
        'implements',
        'import',
        'in',
        'interface',
        'is',
        'late',
        'library',
        'mixin',
        'new',
        'null',
        'of',
        'on',
        'operator',
        'part',
        'required',
        'rethrow',
        'return',
        'set',
        'show',
        'static',
        'super',
        'switch',
        'sync',
        'this',
        'throw',
        'true',
        'try',
        'typedef',
        'var',
        'void',
        'while',
        'with',
        'yield',
      },
      'js' || 'jsx' || 'ts' || 'tsx' => const {
        'async',
        'await',
        'break',
        'case',
        'catch',
        'class',
        'const',
        'continue',
        'debugger',
        'default',
        'delete',
        'do',
        'else',
        'export',
        'extends',
        'false',
        'finally',
        'for',
        'function',
        'if',
        'import',
        'in',
        'instanceof',
        'let',
        'new',
        'null',
        'return',
        'static',
        'super',
        'switch',
        'this',
        'throw',
        'true',
        'try',
        'typeof',
        'var',
        'void',
        'while',
        'with',
        'yield',
      },
      'py' => const {
        'and',
        'as',
        'assert',
        'async',
        'await',
        'break',
        'class',
        'continue',
        'def',
        'del',
        'elif',
        'else',
        'except',
        'False',
        'finally',
        'for',
        'from',
        'global',
        'if',
        'import',
        'in',
        'is',
        'lambda',
        'None',
        'nonlocal',
        'not',
        'or',
        'pass',
        'raise',
        'return',
        'True',
        'try',
        'while',
        'with',
        'yield',
      },
      'json' => const {'true', 'false', 'null'},
      _ => const <String>{},
    };
  }

  static String? _matchComment(String text, int index, String? extension) {
    if (text.startsWith('//', index)) return '//';
    if (text.startsWith('#', index) &&
        (extension == 'py' || extension == 'yaml' || extension == 'yml')) {
      return '#';
    }
    return null;
  }

  static String? _matchString(String text, int index) {
    final quote = text[index];
    if (quote != '"' && quote != "'") return null;

    final buffer = StringBuffer()..write(quote);
    var i = index + 1;
    while (i < text.length) {
      final ch = text[i];
      buffer.write(ch);
      if (ch == '\\') {
        if (i + 1 < text.length) {
          buffer.write(text[i + 1]);
          i += 2;
          continue;
        }
        break;
      }
      if (ch == quote) {
        i++;
        break;
      }
      i++;
    }
    return buffer.toString();
  }

  TextStyle _mergeStyle(TextStyle base, TextStyle? themed) {
    if (themed == null) return base;
    return base.merge(themed);
  }
}
