import 'package:flutter/material.dart';

import '../../models/keyboard_shortcut_action.dart';
import 'keyboard_shortcut_bindings.dart';

/// Inserts a newline at the current selection in [controller].
TextEditingValue insertNewlineAtSelection(TextEditingController controller) {
  final value = controller.value;
  final text = value.text;
  final selection = value.selection.isValid
      ? value.selection
      : TextSelection.collapsed(offset: text.length);
  final start = selection.start;
  final end = selection.end;
  final newText = text.replaceRange(start, end, '\n');
  return value.copyWith(
    text: newText,
    selection: TextSelection.collapsed(offset: start + 1),
    composing: TextRange.empty,
  );
}

/// Key handler for multiline compose fields (landing prompt, future chat drafts).
class ComposeKeyboardShortcutHandler {
  ComposeKeyboardShortcutHandler({
    required this.controller,
    required this.onSubmit,
    required this.canSubmit,
    KeyboardShortcutBindings? bindings,
  }) : bindings = bindings ?? KeyboardShortcutBindings.compose;

  final TextEditingController controller;
  final VoidCallback onSubmit;
  final bool Function() canSubmit;
  final KeyboardShortcutBindings bindings;

  KeyEventResult handle(FocusNode node, KeyEvent event) {
    final action = bindings.match(event);
    switch (action) {
      case KeyboardShortcutAction.composeNewLine:
        controller.value = insertNewlineAtSelection(controller);
        return KeyEventResult.handled;
      case KeyboardShortcutAction.composeSubmit:
        if (canSubmit()) onSubmit();
        return KeyEventResult.handled;
      case null:
        return KeyEventResult.ignored;
    }
  }

  /// Attach to a [FocusNode] used by a compose [TextField].
  static FocusOnKeyEventCallback keyHandler({
    required TextEditingController controller,
    required VoidCallback onSubmit,
    required bool Function() canSubmit,
    KeyboardShortcutBindings? bindings,
  }) {
    final handler = ComposeKeyboardShortcutHandler(
      controller: controller,
      onSubmit: onSubmit,
      canSubmit: canSubmit,
      bindings: bindings,
    );
    return handler.handle;
  }
}
