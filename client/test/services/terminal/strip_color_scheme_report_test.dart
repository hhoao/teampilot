import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';

Uint8List _bytes(List<int> b) => Uint8List.fromList(b);

void main() {
  group('stripColorSchemeReport', () {
    test('removes ESC]997;1 with ST (ESC backslash) terminator', () {
      final input = _bytes([
        0x41, // 'A'
        0x1b, 0x5d, 0x39, 0x39, 0x37, 0x3b, 0x31, // ESC]997;1
        0x1b, 0x5c, // ST
        0x42, // 'B'
      ]);
      expect(stripColorSchemeReport(input), _bytes([0x41, 0x42]));
    });

    test('removes ESC]997;2 with BEL terminator', () {
      final input = _bytes([
        0x1b, 0x5d, 0x39, 0x39, 0x37, 0x3b, 0x32, 0x07, // ESC]997;2 BEL
        0x68, 0x69, // 'hi'
      ]);
      expect(stripColorSchemeReport(input), _bytes([0x68, 0x69]));
    });

    test('leaves unrelated OSC sequences untouched', () {
      // ESC]11;rgb:... BEL  (background query response — must survive)
      final osc11 = _bytes([
        0x1b, 0x5d, 0x31, 0x31, 0x3b, 0x78, 0x07,
      ]);
      expect(stripColorSchemeReport(osc11), osc11);
    });

    test('passes through plain output', () {
      final plain = _bytes([0x68, 0x65, 0x6c, 0x6c, 0x6f]);
      expect(stripColorSchemeReport(plain), plain);
    });
  });
}
