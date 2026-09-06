import 'package:flutter/services.dart';

import 'command_bus.dart';
import 'command_catalog.dart';
import 'command_definition.dart';
import 'double_shift_detector.dart';
import 'key_chord.dart';
import 'keybinding_resolver.dart';
import 'shortcut_context.dart';
import '../keyboard/ime_composing.dart';

/// Matches every [KeyDownEvent] against the effective keybindings and, on a
/// match, invokes the corresponding command id on [CommandBus] — regardless
/// of whether a handler is currently registered for it.
///
/// One instance is installed near the app root via [attach] (see
/// `ShortcutDispatcherHost` in `main.dart`) and lives for the app's lifetime.
/// See docs/superpowers/specs/2026-07-11-keyboard-shortcuts-platform-design.md.
class ShortcutDispatcher {
  ShortcutDispatcher({
    required CommandBus bus,
    required List<KeyChord> Function(String commandId) effectiveChords,
    required ShortcutContext Function() context,
    required bool Function() isMacOS,
    List<CommandDefinition>? catalog,
    DoubleShiftDetector? doubleShiftDetector,
    bool Function()? isImeComposing,
  }) : _bus = bus,
       _effectiveChords = effectiveChords,
       _context = context,
       _isMacOS = isMacOS,
       _catalog = catalog ?? CommandCatalog.v1,
       _doubleShiftDetector = doubleShiftDetector ?? DoubleShiftDetector(),
       _isImeComposing = isImeComposing ?? imeCompositionActive;

  final CommandBus _bus;
  final List<KeyChord> Function(String commandId) _effectiveChords;
  final ShortcutContext Function() _context;
  final bool Function() _isMacOS;
  final List<CommandDefinition> _catalog;
  final DoubleShiftDetector _doubleShiftDetector;
  final bool Function() _isImeComposing;

  /// Set to `false` to temporarily suspend all shortcut matching (e.g. while
  /// a modal keyboard grab, such as a rebind-capture dialog, is active).
  bool enabled = true;

  /// Returns `true` if [event] matched a command and was forwarded to the
  /// bus, `false` if it should keep propagating normally.
  bool handle(KeyEvent event) {
    if (!enabled) return false;

    if (event is! KeyDownEvent) return false;

    // While an IME composition is active (candidate window up), the input
    // method owns the bare keys — Enter commits the raw composition, Escape
    // cancels it, arrows move the candidate selection. Stand down so the key
    // reaches the IME instead of e.g. submitting a half-typed chat draft.
    // Modifier combos still fire: the IME passes them through to the app.
    if (_imeOwnsEvent()) return false;

    if (_doubleShiftDetector.feed(event)) {
      final commandId = _matchDoubleTapShift();
      if (commandId != null) {
        _bus.invoke(commandId);
        return true;
      }
    }

    final effectiveByCommand = <String, List<KeyChord>>{
      for (final def in _catalog) def.id: _effectiveChords(def.id),
    };

    final commandId = KeybindingResolver.match(
      event: event,
      effectiveByCommand: effectiveByCommand,
      context: _context(),
      isMacOS: _isMacOS(),
      catalog: _catalog,
    );
    if (commandId == null) return false;

    // Silent no-op when nothing is registered — still counts as handled so
    // the key doesn't fall through to e.g. a terminal PTY while chrome that
    // will eventually own this command is still mounting.
    _bus.invoke(commandId);
    return true;
  }

  /// Whether the active IME composition should consume this key event
  /// instead of shortcut matching: bare keys belong to the IME (Enter
  /// commits the raw composition, arrows move the candidate selection),
  /// while command modifier combos (Ctrl / Cmd / Alt) stay app-owned,
  /// matching native macOS behavior. Shift alone stays IME-owned.
  bool _imeOwnsEvent() {
    if (!_isImeComposing()) return false;
    final keyboard = HardwareKeyboard.instance;
    return !(keyboard.isControlPressed ||
        keyboard.isMetaPressed ||
        keyboard.isAltPressed);
  }

  String? _matchDoubleTapShift() {
    final context = _context();
    for (final def in _catalog) {
      final chords = _effectiveChords(def.id);
      if (!chords.any((c) => c.doubleTap && c.key == 'shift')) continue;
      if (!def.when.isSatisfiedBy(context)) continue;
      if (context.inTerminal && !def.terminalPassthrough) continue;
      return def.id;
    }
    return null;
  }

  void attach() {
    HardwareKeyboard.instance.addHandler(handle);
  }

  void detach() {
    HardwareKeyboard.instance.removeHandler(handle);
  }
}
