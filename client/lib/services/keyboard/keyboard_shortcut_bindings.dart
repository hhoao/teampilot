import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../models/keyboard_shortcut_action.dart';

/// Default and user-overridable keyboard bindings for app actions.
///
/// Future global shortcut settings can load overrides from disk and call
/// [mergeWith] before dispatching key events.
class KeyboardShortcutBindings {
  const KeyboardShortcutBindings._({
    required Map<KeyboardShortcutAction, List<ShortcutActivator>>
    activatorsByAction,
    required List<KeyboardShortcutAction> matchPriority,
  }) : _activatorsByAction = activatorsByAction,
       _matchPriority = matchPriority;

  final Map<KeyboardShortcutAction, List<ShortcutActivator>>
  _activatorsByAction;
  final List<KeyboardShortcutAction> _matchPriority;

  /// Builds a custom binding set (user prefs deserialization, tests).
  factory KeyboardShortcutBindings.fromActivators({
    required Map<KeyboardShortcutAction, List<ShortcutActivator>>
    activatorsByAction,
    List<KeyboardShortcutAction>? matchPriority,
  }) => KeyboardShortcutBindings._(
    activatorsByAction: activatorsByAction,
    matchPriority: matchPriority ?? activatorsByAction.keys.toList(),
  );

  /// Compose field: Enter submits, Ctrl/Cmd+Enter inserts a newline.
  static final compose = KeyboardShortcutBindings._(
    activatorsByAction: {
      KeyboardShortcutAction.composeNewLine: const [
        SingleActivator(LogicalKeyboardKey.enter, control: true),
        SingleActivator(LogicalKeyboardKey.enter, meta: true),
      ],
      KeyboardShortcutAction.composeSubmit: const [
        SingleActivator(
          LogicalKeyboardKey.enter,
          control: false,
          shift: false,
          alt: false,
          meta: false,
        ),
      ],
    },
    matchPriority: const [
      KeyboardShortcutAction.composeNewLine,
      KeyboardShortcutAction.composeSubmit,
    ],
  );

  Iterable<KeyboardShortcutAction> get actions => _matchPriority;

  List<ShortcutActivator> activatorsFor(KeyboardShortcutAction action) =>
      List.unmodifiable(_activatorsByAction[action] ?? const []);

  /// User prefs (or feature flags) replace bindings per action; unspecified
  /// actions keep [base] defaults.
  KeyboardShortcutBindings mergeWith(KeyboardShortcutBindings? overrides) {
    if (overrides == null) return this;
    final merged = Map<KeyboardShortcutAction, List<ShortcutActivator>>.from(
      _activatorsByAction,
    );
    for (final entry in overrides._activatorsByAction.entries) {
      merged[entry.key] = List<ShortcutActivator>.from(entry.value);
    }
    return KeyboardShortcutBindings._(
      activatorsByAction: merged,
      matchPriority: overrides._matchPriority.isNotEmpty
          ? overrides._matchPriority
          : _matchPriority,
    );
  }

  /// Returns the highest-priority action whose activator accepts [event].
  KeyboardShortcutAction? match(KeyEvent event) {
    if (event is! KeyDownEvent) return null;
    final keyboard = HardwareKeyboard.instance;
    for (final action in _matchPriority) {
      for (final activator in _activatorsByAction[action] ?? const []) {
        if (activator.accepts(event, keyboard)) return action;
      }
    }
    return null;
  }
}
