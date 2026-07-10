import 'package:flutter/material.dart';

import '../commands/command_bus.dart';
import '../commands/command_ids.dart';

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

/// Registers `compose.submit` / `compose.newline` handlers for a focused
/// compose field on the root [CommandBus].
///
/// The root [ShortcutDispatcher] (see `main.dart`'s `ShortcutDispatcherHost`)
/// owns matching Enter / Mod+Enter against the catalog and invokes these ids
/// unconditionally when `inCompose` is true; the field only needs to own
/// *what happens* when its command fires, for as long as it holds focus.
abstract final class ComposeCommandBindings {
  /// Registers handlers for the currently-focused compose field and returns
  /// a disposer that unregisters them — call on focus loss / widget dispose.
  static VoidCallback register({
    required CommandBus bus,
    required TextEditingController controller,
    required VoidCallback onSubmit,
    required bool Function() canSubmit,
  }) {
    void submitHandler() {
      if (canSubmit()) onSubmit();
    }

    void newlineHandler() {
      controller.value = insertNewlineAtSelection(controller);
    }

    bus.register(CommandIds.composeSubmit, submitHandler);
    bus.register(CommandIds.composeNewline, newlineHandler);

    return () {
      bus.unregister(CommandIds.composeSubmit, submitHandler);
      bus.unregister(CommandIds.composeNewline, newlineHandler);
    };
  }
}
