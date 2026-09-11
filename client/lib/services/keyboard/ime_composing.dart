import 'package:flutter/widgets.dart';

/// Whether the currently focused editable text has an active IME composition
/// (marked text with the input-method candidate window up).
///
/// While a composition is active the input method owns the bare keys — Enter
/// commits the raw composition instead of the field's submit action, Escape
/// cancels it, arrows move the candidate selection — so global shortcut
/// matching must stand down and let the key event reach the IME. See
/// [ShortcutDispatcher] in `services/commands/shortcut_dispatcher.dart`.
bool imeCompositionActive() {
  final focusContext = FocusManager.instance.primaryFocus?.context;
  if (focusContext == null) return false;
  final editable = focusContext.findAncestorStateOfType<EditableTextState>();
  if (editable == null) return false;
  // TextRange.empty (-1, -1) means no composition; a valid non-collapsed
  // range is the marked region currently being composed.
  final composing = editable.widget.controller.value.composing;
  return composing.isValid && !composing.isCollapsed;
}
