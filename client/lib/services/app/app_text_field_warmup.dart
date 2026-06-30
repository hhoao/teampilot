import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';

import '../../theme/app_outline_input_theme.dart';

/// Canonical [TextField] layouts warmed once per session so the first real
/// [RenderEditable] does not pay cold-start layout on a user-facing frame.
///
/// Glyph shaping runs earlier in [UiInteractiveWarmup]; this needs a mounted
/// [MaterialApp] theme (input decoration, icons, density) and must stay out of
/// [buildLightTheme] bootstrap to avoid startup stalls.
abstract final class AppTextFieldWarmup {
  AppTextFieldWarmup._();

  static const fieldWidth = 360.0;
  static const singleLineHeight = 44.0;
  static const multilineHeight = 96.0;

  static var _readyForSession = false;
  static Completer<void>? _whenReadyCompleter;

  /// Completes after every [profiles] variant has been laid out off-screen, or
  /// immediately in tests / when already warmed this session.
  static Future<void> get whenReady {
    if (_inTest || _readyForSession) return Future<void>.value();
    return (_whenReadyCompleter ??= Completer<void>()).future;
  }

  static bool get isReady => _inTest || _readyForSession;

  static void markReady() {
    if (_readyForSession) return;
    _readyForSession = true;
    final completer = _whenReadyCompleter;
    _whenReadyCompleter = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }

  static bool get _inTest {
    try {
      return Platform.environment.containsKey('FLUTTER_TEST');
    } on Object {
      return false;
    }
  }

  /// Representative fields covering the app's shared [InputDecorationTheme] and
  /// the most common overrides (search prefix, multiline bodies).
  static final List<Widget Function(BuildContext context)> profiles = [
    _standardOutline,
    _prefixIconSearch,
    _multilineOutline,
  ];

  static Widget _warmupMaterial(BuildContext context, Widget child) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: child,
    );
  }

  static Widget _standardOutline(BuildContext context) {
    return _warmupMaterial(
      context,
      TextField(
        decoration: const InputDecoration(hintText: 'a'),
        style: appTextFieldStyle(Theme.of(context).textTheme),
      ),
    );
  }

  static Widget _prefixIconSearch(BuildContext context) {
    return _warmupMaterial(
      context,
      TextField(
        decoration: InputDecoration(
          hintText: 'a',
          prefixIcon: Icon(
            Icons.search,
            size: context.appIconSizes.md,
          ),
          floatingLabelBehavior: FloatingLabelBehavior.never,
        ),
        style: appTextFieldStyle(Theme.of(context).textTheme),
      ),
    );
  }

  static Widget _multilineOutline(BuildContext context) {
    return _warmupMaterial(
      context,
      TextField(
        decoration: const InputDecoration(hintText: 'a'),
        style: appTextFieldStyle(Theme.of(context).textTheme),
        minLines: 3,
        maxLines: 5,
      ),
    );
  }
}
