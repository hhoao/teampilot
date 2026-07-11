import 'dart:ui' show Brightness;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/editor_platform/editor_syntax_theme.dart';

void main() {
  test('falls back from keyword.control to keyword', () {
    final theme = EditorSyntaxTheme.atomOneDark();
    expect(theme.styleFor('keyword.control'), isNotNull);
    expect(theme.styleFor('keyword.control'), theme.styleFor('keyword'));
  });

  test('unknown scope resolves to null', () {
    final theme = EditorSyntaxTheme.atomOneDark();
    expect(theme.styleFor('totally.unknown.scope'), isNull);
  });

  test('exact match is preferred over a parent scope', () {
    final theme = EditorSyntaxTheme.atomOneDark();
    final stringStyle = theme.styleFor('string');
    final escapeStyle = theme.styleFor('string.escape');
    expect(escapeStyle, isNotNull);
    expect(escapeStyle, isNot(equals(stringStyle)));
  });

  test('atomOneDark and atomOneLight factories exist and differ', () {
    final dark = EditorSyntaxTheme.atomOneDark();
    final light = EditorSyntaxTheme.atomOneLight();
    expect(dark.styleFor('keyword')?.color, isNot(equals(light.styleFor('keyword')?.color)));
  });

  test('forBrightness picks dark for Brightness.dark and light otherwise', () {
    final dark = EditorSyntaxTheme.forBrightness(Brightness.dark);
    final light = EditorSyntaxTheme.forBrightness(Brightness.light);
    expect(dark.styleFor('keyword')?.color, EditorSyntaxTheme.atomOneDark().styleFor('keyword')?.color);
    expect(light.styleFor('keyword')?.color, EditorSyntaxTheme.atomOneLight().styleFor('keyword')?.color);
  });

  test('asStyleMap exposes an unmodifiable snapshot of scope styles', () {
    final theme = EditorSyntaxTheme.atomOneDark();
    final map = theme.asStyleMap();
    expect(map['keyword'], theme.styleFor('keyword'));
    expect(() => map['keyword'] = const TextStyle(), throwsUnsupportedError);
  });

  test('nested fallback walks multiple dotted levels', () {
    final theme = EditorSyntaxTheme.atomOneDark();
    expect(theme.styleFor('variable.parameter.builtin'), theme.styleFor('variable.parameter'));
  });
}
