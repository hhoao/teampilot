import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/commands/key_chord.dart';
import 'package:teampilot/services/commands/key_chord_formatter.dart';

void main() {
  test('round-trips JSON', () {
    const chord = KeyChord(key: 'w', mods: [KeyChordMod.mod]);
    expect(KeyChord.fromJson(chord.toJson()), chord);
  });

  test('mod resolves to meta on macOS target, control otherwise', () {
    final activator = const KeyChord(
      key: 'w',
      mods: [KeyChordMod.mod],
    ).toActivator(isMacOS: true);
    expect(activator, isA<SingleActivator>());
    final mac = activator as SingleActivator;
    expect(mac.trigger, LogicalKeyboardKey.keyW);
    expect(mac.meta, isTrue);
    expect(mac.control, isFalse);

    final win = const KeyChord(
      key: 'w',
      mods: [KeyChordMod.mod],
    ).toActivator(isMacOS: false) as SingleActivator;
    expect(win.control, isTrue);
    expect(win.meta, isFalse);
  });

  test('explicit ctrl stays ctrl on macOS', () {
    final a = const KeyChord(
      key: 'tab',
      mods: [KeyChordMod.ctrl],
    ).toActivator(isMacOS: true) as SingleActivator;
    expect(a.control, isTrue);
    expect(a.meta, isFalse);
  });

  test('formatter uses symbols on macOS', () {
    expect(
      formatKeyChord(
        const KeyChord(key: 'w', mods: [KeyChordMod.mod]),
        isMacOS: true,
      ),
      '⌘W',
    );
    expect(
      formatKeyChord(
        const KeyChord(key: 'w', mods: [KeyChordMod.mod]),
        isMacOS: false,
      ),
      'Ctrl+W',
    );
  });

  test('hasModifiers is false only for bare keys', () {
    expect(const KeyChord(key: 'enter').hasModifiers, isFalse);
    expect(
      const KeyChord(key: 'enter', mods: [KeyChordMod.mod]).hasModifiers,
      isTrue,
    );
  });
}
