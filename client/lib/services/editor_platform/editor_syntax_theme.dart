import 'dart:ui' show Brightness;

import 'package:flutter/painting.dart';

/// TextMate-style scope → [TextStyle] lookup for tree-sitter highlight
/// captures (e.g. `keyword.control`, `string.escape`), aligned with the
/// app's existing atom-one-dark / atom-one-light look. Language packs stay
/// theme-agnostic: they only emit scope names, never colors.
class EditorSyntaxTheme {
  const EditorSyntaxTheme._(this._scopes);

  /// Dark palette matching `re_highlight`'s atom-one-dark theme.
  factory EditorSyntaxTheme.atomOneDark() =>
      const EditorSyntaxTheme._(_atomOneDarkScopes);

  /// Light palette matching `re_highlight`'s atom-one-light theme.
  factory EditorSyntaxTheme.atomOneLight() =>
      const EditorSyntaxTheme._(_atomOneLightScopes);

  /// Picks the dark or light palette for [brightness].
  factory EditorSyntaxTheme.forBrightness(Brightness brightness) {
    return brightness == Brightness.dark
        ? EditorSyntaxTheme.atomOneDark()
        : EditorSyntaxTheme.atomOneLight();
  }

  final Map<String, TextStyle> _scopes;

  /// Resolves [scope] by walking from most specific to least specific,
  /// e.g. `keyword.control.conditional` tries itself, then
  /// `keyword.control`, then `keyword`. Returns `null` when neither the
  /// scope nor any of its ancestors has a style — callers should fall back
  /// to the editor's default text color rather than substituting a scope.
  TextStyle? styleFor(String scope) {
    var current = scope;
    while (true) {
      final style = _scopes[current];
      if (style != null) {
        return style;
      }
      final dotIndex = current.lastIndexOf('.');
      if (dotIndex == -1) {
        return null;
      }
      current = current.substring(0, dotIndex);
    }
  }

  /// Snapshot of the scope → style map, e.g. for `CodeEditorStyle.syntaxTheme`.
  Map<String, TextStyle> asStyleMap() => Map.unmodifiable(_scopes);
}

// Colors copied from `re_highlight`'s atom-one-dark.dart / atom-one-light.dart
// so tree-sitter captures paint the same palette as the previous highlighter.
const _kDarkForeground = Color(0xffabb2bf);
const _kDarkComment = Color(0xff5c6370);
const _kDarkKeyword = Color(0xffc678dd);
const _kDarkSection = Color(0xffe06c75);
const _kDarkLiteral = Color(0xff56b6c2);
const _kDarkString = Color(0xff98c379);
const _kDarkAttr = Color(0xffd19a66);
const _kDarkTitle = Color(0xff61aeee);
const _kDarkBuiltin = Color(0xffe6c07b);

const _kLightForeground = Color(0xff383a42);
const _kLightComment = Color(0xffa0a1a7);
const _kLightKeyword = Color(0xffa626a4);
const _kLightSection = Color(0xffe45649);
const _kLightLiteral = Color(0xff0184bb);
const _kLightString = Color(0xff50a14f);
const _kLightAttr = Color(0xff986801);
const _kLightTitle = Color(0xff4078f2);
const _kLightBuiltin = Color(0xffc18401);

const _atomOneDarkScopes = <String, TextStyle>{
  'comment': TextStyle(color: _kDarkComment),

  'keyword': TextStyle(color: _kDarkKeyword),
  'operator': TextStyle(color: _kDarkForeground),

  'string': TextStyle(color: _kDarkString),
  'string.escape': TextStyle(color: _kDarkLiteral),

  'number': TextStyle(color: _kDarkAttr),
  'constant': TextStyle(color: _kDarkLiteral),
  'constant.builtin': TextStyle(color: _kDarkLiteral),

  'property': TextStyle(color: _kDarkAttr),
  'variable': TextStyle(color: _kDarkForeground),
  'variable.builtin': TextStyle(color: _kDarkBuiltin),
  'variable.parameter': TextStyle(color: _kDarkAttr),

  'function': TextStyle(color: _kDarkTitle),
  'function.builtin': TextStyle(color: _kDarkBuiltin),
  'constructor': TextStyle(color: _kDarkBuiltin),

  'type': TextStyle(color: _kDarkAttr),
  'type.builtin': TextStyle(color: _kDarkBuiltin),

  'tag': TextStyle(color: _kDarkSection),
  'tag.attribute': TextStyle(color: _kDarkString),
  'attribute': TextStyle(color: _kDarkString),
  'label': TextStyle(color: _kDarkSection),

  'punctuation': TextStyle(color: _kDarkForeground),

  'emphasis': TextStyle(fontStyle: FontStyle.italic),
  'strong': TextStyle(fontWeight: FontWeight.bold),
};

const _atomOneLightScopes = <String, TextStyle>{
  'comment': TextStyle(color: _kLightComment),

  'keyword': TextStyle(color: _kLightKeyword),
  'operator': TextStyle(color: _kLightForeground),

  'string': TextStyle(color: _kLightString),
  'string.escape': TextStyle(color: _kLightLiteral),

  'number': TextStyle(color: _kLightAttr),
  'constant': TextStyle(color: _kLightLiteral),
  'constant.builtin': TextStyle(color: _kLightLiteral),

  'property': TextStyle(color: _kLightAttr),
  'variable': TextStyle(color: _kLightForeground),
  'variable.builtin': TextStyle(color: _kLightBuiltin),
  'variable.parameter': TextStyle(color: _kLightAttr),

  'function': TextStyle(color: _kLightTitle),
  'function.builtin': TextStyle(color: _kLightBuiltin),
  'constructor': TextStyle(color: _kLightBuiltin),

  'type': TextStyle(color: _kLightAttr),
  'type.builtin': TextStyle(color: _kLightBuiltin),

  'tag': TextStyle(color: _kLightSection),
  'tag.attribute': TextStyle(color: _kLightString),
  'attribute': TextStyle(color: _kLightString),
  'label': TextStyle(color: _kLightSection),

  'punctuation': TextStyle(color: _kLightForeground),

  'emphasis': TextStyle(fontStyle: FontStyle.italic),
  'strong': TextStyle(fontWeight: FontWeight.bold),
};
