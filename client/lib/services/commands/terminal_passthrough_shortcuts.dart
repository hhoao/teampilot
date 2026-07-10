import 'package:flutter/widgets.dart';

import 'command_catalog.dart';
import 'command_definition.dart';
import 'key_chord.dart';

/// Builds a `TerminalView.shortcuts` overlay that claims every effective
/// chord of a `terminalPassthrough` command, so the terminal engine's own
/// `Focus.onKeyEvent` bails out before it reaches `encodeKey`/PTY-write for
/// a key the root `ShortcutDispatcher` already owns.
///
/// Why this is needed (Task 11): `HardwareKeyboard.addHandler` handlers
/// (the dispatcher) and a focused widget's `Focus.onKeyEvent` (the
/// terminal's own key handling, installed by `flutter_alacritty`'s
/// `TerminalView`) are independent destinations of the *same* key event —
/// Flutter's `KeyEventManager` always calls both, regardless of either's
/// return value (see `HardwareKeyboard`'s `handleKeyData` /
/// `handleRawKeyMessage`). So the dispatcher returning `handled` does
/// *not* stop the terminal from also encoding the key and writing bytes to
/// the PTY — e.g. Ctrl+Tab / Ctrl+W / Ctrl+B / Ctrl+J are real control
/// bytes (tab-cycle, ETB, STX, linefeed) the shell would otherwise receive
/// alongside the app command firing. Merging this overlay into
/// `TerminalView(shortcuts: ...)` makes a matching key event `return`
/// inside `TerminalView._onKeyFallback` before it reaches `encodeKey`,
/// regardless of whether any `Action` ends up bound to the intent — see
/// docs/superpowers/specs/2026-07-11-keyboard-shortcuts-platform-design.md
/// ("Terminal widgets must not swallow Mod chords before the dispatcher").
Map<ShortcutActivator, Intent> terminalPassthroughShortcutOverlay({
  required Map<String, List<KeyChord>> effectiveByCommand,
  required bool isMacOS,
  List<CommandDefinition>? catalog,
}) {
  final overlay = <ShortcutActivator, Intent>{};
  for (final def in catalog ?? CommandCatalog.v1) {
    if (!def.terminalPassthrough) continue;
    for (final chord in effectiveByCommand[def.id] ?? const <KeyChord>[]) {
      overlay[chord.toActivator(isMacOS: isMacOS)] =
          const DoNothingAndStopPropagationIntent();
    }
  }
  return overlay;
}
