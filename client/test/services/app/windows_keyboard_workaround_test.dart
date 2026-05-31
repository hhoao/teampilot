import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/app/windows_keyboard_workaround.dart';

void main() {
  group('patchWindowsAltModifierMessage', () {
    test('patches left Alt keydown with zero modifiers', () {
      final result = patchWindowsAltModifierMessage(<String, Object?>{
        'keymap': 'windows',
        'type': 'keydown',
        'keyCode': 164,
        'scanCode': 56,
        'modifiers': 0,
      });

      expect(result, isA<Map>());
      final map = result! as Map;
      expect(map['modifiers'], (1 << 7) | (1 << 6));
    });

    test('patches right Alt keydown with zero modifiers', () {
      final result = patchWindowsAltModifierMessage(<String, Object?>{
        'keymap': 'windows',
        'type': 'keydown',
        'keyCode': 165,
        'modifiers': 0,
      });

      final map = result! as Map;
      expect(map['modifiers'], (1 << 8) | (1 << 6));
    });

    test('leaves non-Alt keys unchanged', () {
      final message = <String, Object?>{
        'keymap': 'windows',
        'type': 'keydown',
        'keyCode': 65,
        'modifiers': 0,
      };
      expect(patchWindowsAltModifierMessage(message), same(message));
    });

    test('leaves keyup unchanged', () {
      final message = <String, Object?>{
        'keymap': 'windows',
        'type': 'keyup',
        'keyCode': 164,
        'modifiers': 0,
      };
      expect(patchWindowsAltModifierMessage(message), same(message));
    });
  });
}
