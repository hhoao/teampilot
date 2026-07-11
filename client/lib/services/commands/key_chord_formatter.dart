import 'key_chord.dart';

/// Formats a portable [KeyChord] for display in settings, cheatsheets, and menus.
String formatKeyChord(KeyChord chord, {required bool isMacOS}) {
  final parts = <String>[
    for (final mod in chord.mods) _formatModifier(mod, isMacOS: isMacOS),
    _formatKey(chord.key),
  ];
  return isMacOS ? parts.join() : parts.join('+');
}

String _formatModifier(KeyChordMod mod, {required bool isMacOS}) {
  if (isMacOS) {
    return switch (mod) {
      KeyChordMod.mod || KeyChordMod.meta => '⌘',
      KeyChordMod.shift => '⇧',
      KeyChordMod.alt => '⌥',
      KeyChordMod.ctrl => '⌃',
    };
  }

  return switch (mod) {
    KeyChordMod.mod || KeyChordMod.ctrl => 'Ctrl',
    KeyChordMod.shift => 'Shift',
    KeyChordMod.alt => 'Alt',
    KeyChordMod.meta => 'Meta',
  };
}

String _formatKey(String key) {
  if (key.length == 1) {
    return key.toUpperCase();
  }

  return switch (key) {
    'tab' => 'Tab',
    'equal' => '=',
    'minus' => '-',
    'digit0' => '0',
    'digit1' => '1',
    'digit2' => '2',
    'digit3' => '3',
    'digit4' => '4',
    'digit5' => '5',
    'digit6' => '6',
    'digit7' => '7',
    'digit8' => '8',
    'digit9' => '9',
    'enter' => 'Enter',
    'slash' => '/',
    'arrowLeft' => '←',
    'arrowRight' => '→',
    'numpadAdd' => 'Num+',
    'numpadSubtract' => 'Num-',
    'f5' => 'F5',
    _ => key,
  };
}
