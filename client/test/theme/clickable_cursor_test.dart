import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/theme/app_theme.dart';

void main() {
  group('Material button themes resolve hand cursor on desktop', () {
    for (final (name, builder) in <(String, ThemeData Function())>[
      ('light', buildLightTheme),
      ('dark', buildDarkTheme),
    ]) {
      test('$name: filled/outlined/elevated/text/icon buttons -> click', () {
        final theme = builder();
        for (final cursor in <MouseCursor?>[
          theme.filledButtonTheme.style?.mouseCursor?.resolve(const <WidgetState>{}),
          theme.outlinedButtonTheme.style?.mouseCursor?.resolve(const <WidgetState>{}),
          theme.elevatedButtonTheme.style?.mouseCursor?.resolve(const <WidgetState>{}),
          theme.textButtonTheme.style?.mouseCursor?.resolve(const <WidgetState>{}),
          theme.iconButtonTheme.style?.mouseCursor?.resolve(const <WidgetState>{}),
        ]) {
          expect(cursor, SystemMouseCursors.click, reason: name);
        }
      });

      test('$name: disabled buttons -> basic arrow', () {
        final theme = builder();
        for (final cursor in <MouseCursor?>[
          theme.filledButtonTheme.style?.mouseCursor?.resolve(const {WidgetState.disabled}),
          theme.outlinedButtonTheme.style?.mouseCursor?.resolve(const {WidgetState.disabled}),
          theme.elevatedButtonTheme.style?.mouseCursor?.resolve(const {WidgetState.disabled}),
          theme.textButtonTheme.style?.mouseCursor?.resolve(const {WidgetState.disabled}),
          theme.iconButtonTheme.style?.mouseCursor?.resolve(const {WidgetState.disabled}),
        ]) {
          expect(cursor, SystemMouseCursors.basic, reason: name);
        }
      });
    }
  });
}
