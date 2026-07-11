import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, listEquals;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Portable modifier tokens for persisted key chords.
///
/// [mod] resolves to Meta on macOS and Control elsewhere at activation time.
enum KeyChordMod { mod, shift, alt, ctrl, meta }

/// Platform-neutral keyboard chord persisted in keybinding overrides.
class KeyChord {
  const KeyChord._({required this.key, required this.mods});

  factory KeyChord({required String key, List<KeyChordMod> mods = const []}) {
    return KeyChord._(
      key: canonicalChordKey(key),
      mods: canonicalChordMods(mods),
    );
  }

  final String key;
  final List<KeyChordMod> mods;

  bool get hasModifiers => mods.isNotEmpty;

  Map<String, dynamic> toJson() => {
    'key': key,
    'mods': mods.map((mod) => mod.name).toList(),
  };

  factory KeyChord.fromJson(Map<String, dynamic> json) {
    final rawMods = json['mods'];
    return KeyChord(
      key: json['key'] as String,
      mods: rawMods is List
          ? rawMods
                .cast<String>()
                .map(KeyChordMod.values.byName)
                .toList(growable: false)
          : const [],
    );
  }

  ShortcutActivator toActivator({required bool isMacOS}) {
    var control = false;
    var shift = false;
    var alt = false;
    var meta = false;

    for (final mod in mods) {
      switch (mod) {
        case KeyChordMod.mod:
          if (isMacOS) {
            meta = true;
          } else {
            control = true;
          }
        case KeyChordMod.shift:
          shift = true;
        case KeyChordMod.alt:
          alt = true;
        case KeyChordMod.ctrl:
          control = true;
        case KeyChordMod.meta:
          meta = true;
      }
    }

    return SingleActivator(
      logicalKeyForChordKey(key),
      control: control,
      shift: shift,
      alt: alt,
      meta: meta,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KeyChord && key == other.key && listEquals(mods, other.mods);

  @override
  int get hashCode => Object.hash(key, Object.hashAll(mods));
}

const _modOrder = <KeyChordMod>[
  KeyChordMod.mod,
  KeyChordMod.ctrl,
  KeyChordMod.meta,
  KeyChordMod.alt,
  KeyChordMod.shift,
];

String canonicalChordKey(String key) {
  if (key.length == 1) {
    final codeUnit = key.codeUnitAt(0);
    if ((codeUnit >= 0x41 && codeUnit <= 0x5A) ||
        (codeUnit >= 0x61 && codeUnit <= 0x7A)) {
      return key.toLowerCase();
    }
  }
  return key;
}

List<KeyChordMod> canonicalChordMods(Iterable<KeyChordMod> mods) {
  final present = mods.toSet();
  return [
    for (final mod in _modOrder)
      if (present.contains(mod)) mod,
  ];
}

/// Default platform probe for production callers that do not inject [isMacOS].
bool defaultIsMacOS() => !kIsWeb && Platform.isMacOS;

LogicalKeyboardKey logicalKeyForChordKey(String key) {
  if (key.length == 1) {
    final codeUnit = key.codeUnitAt(0);
    if (codeUnit >= 0x61 && codeUnit <= 0x7A) {
      return LogicalKeyboardKey(
        LogicalKeyboardKey.keyA.keyId + (codeUnit - 0x61),
      );
    }
    if (codeUnit >= 0x41 && codeUnit <= 0x5A) {
      return LogicalKeyboardKey(
        LogicalKeyboardKey.keyA.keyId + (codeUnit - 0x41),
      );
    }
  }

  return switch (key) {
    'tab' => LogicalKeyboardKey.tab,
    'equal' => LogicalKeyboardKey.equal,
    'minus' => LogicalKeyboardKey.minus,
    'digit0' => LogicalKeyboardKey.digit0,
    'digit1' => LogicalKeyboardKey.digit1,
    'digit2' => LogicalKeyboardKey.digit2,
    'digit3' => LogicalKeyboardKey.digit3,
    'digit4' => LogicalKeyboardKey.digit4,
    'digit5' => LogicalKeyboardKey.digit5,
    'digit6' => LogicalKeyboardKey.digit6,
    'digit7' => LogicalKeyboardKey.digit7,
    'digit8' => LogicalKeyboardKey.digit8,
    'digit9' => LogicalKeyboardKey.digit9,
    'enter' => LogicalKeyboardKey.enter,
    'slash' => LogicalKeyboardKey.slash,
    'arrowLeft' => LogicalKeyboardKey.arrowLeft,
    'arrowRight' => LogicalKeyboardKey.arrowRight,
    'numpadAdd' => LogicalKeyboardKey.numpadAdd,
    'numpadSubtract' => LogicalKeyboardKey.numpadSubtract,
    _ => throw ArgumentError('Unsupported key chord key: $key'),
  };
}

String chordKeyForLogicalKey(LogicalKeyboardKey logicalKey) {
  final keyId = logicalKey.keyId;
  final keyAId = LogicalKeyboardKey.keyA.keyId;
  if (keyId >= keyAId && keyId <= LogicalKeyboardKey.keyZ.keyId) {
    return String.fromCharCode(0x61 + (keyId - keyAId));
  }

  return switch (logicalKey) {
    LogicalKeyboardKey.tab => 'tab',
    LogicalKeyboardKey.equal => 'equal',
    LogicalKeyboardKey.minus => 'minus',
    LogicalKeyboardKey.digit0 => 'digit0',
    LogicalKeyboardKey.digit1 => 'digit1',
    LogicalKeyboardKey.digit2 => 'digit2',
    LogicalKeyboardKey.digit3 => 'digit3',
    LogicalKeyboardKey.digit4 => 'digit4',
    LogicalKeyboardKey.digit5 => 'digit5',
    LogicalKeyboardKey.digit6 => 'digit6',
    LogicalKeyboardKey.digit7 => 'digit7',
    LogicalKeyboardKey.digit8 => 'digit8',
    LogicalKeyboardKey.digit9 => 'digit9',
    LogicalKeyboardKey.enter => 'enter',
    LogicalKeyboardKey.slash => 'slash',
    LogicalKeyboardKey.arrowLeft => 'arrowLeft',
    LogicalKeyboardKey.arrowRight => 'arrowRight',
    LogicalKeyboardKey.numpadAdd => 'numpadAdd',
    LogicalKeyboardKey.numpadSubtract => 'numpadSubtract',
    _ => throw ArgumentError('Unsupported logical key: $logicalKey'),
  };
}
