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
///
/// `compose.submit` and `compose.newline` are registered independently so a
/// field can keep newline active while temporarily un-registering submit
/// (e.g. while its own `@` / `/` suggestion overlay wants to claim bare
/// Enter to pick a suggestion instead of submitting).
abstract final class ComposeCommandBindings {
  /// Registers the `compose.newline` handler and returns a disposer.
  static VoidCallback registerNewline({
    required CommandBus bus,
    required TextEditingController controller,
  }) {
    void newlineHandler() {
      controller.value = insertNewlineAtSelection(controller);
    }

    bus.register(CommandIds.composeNewline, newlineHandler);
    return () => bus.unregister(CommandIds.composeNewline, newlineHandler);
  }

  /// Registers the `compose.submit` handler and returns a disposer.
  static VoidCallback registerSubmit({
    required CommandBus bus,
    required VoidCallback onSubmit,
    required bool Function() canSubmit,
  }) {
    void submitHandler() {
      if (canSubmit()) onSubmit();
    }

    bus.register(CommandIds.composeSubmit, submitHandler);
    return () => bus.unregister(CommandIds.composeSubmit, submitHandler);
  }

  /// Registers both handlers for the currently-focused compose field and
  /// returns a disposer that unregisters them — call on focus loss / widget
  /// dispose. Convenience for callers with no suggestion overlay to gate
  /// submit against; see [registerSubmit] / [registerNewline] to gate them
  /// independently.
  static VoidCallback register({
    required CommandBus bus,
    required TextEditingController controller,
    required VoidCallback onSubmit,
    required bool Function() canSubmit,
  }) {
    final disposeNewline = registerNewline(bus: bus, controller: controller);
    final disposeSubmit = registerSubmit(
      bus: bus,
      onSubmit: onSubmit,
      canSubmit: canSubmit,
    );
    return () {
      disposeNewline();
      disposeSubmit();
    };
  }
}
