import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team_bus/bus_user_line_capture.dart';

void main() {
  test('passes keystrokes through for echo and steals the submitted line', () {
    var intercept = true;
    String? submitted;
    final capture = BusUserLineCapture(
      BusUserInputRouting(
        shouldIntercept: () => intercept,
        onUserLine: (line) => submitted = line,
      ),
    );

    // While parked: printable bytes pass through so the CLI echoes them;
    // Enter is replaced with Ctrl-U (clear the CLI's line) and the buffered
    // line is delivered to the bus.
    expect(
      capture.filter(Uint8List.fromList(utf8.encode('hi\r'))),
      [...utf8.encode('hi'), 0x15],
    );
    expect(submitted, 'hi');

    // Not intercepting: plain passthrough, nothing delivered to the bus.
    submitted = null;
    intercept = false;
    expect(
      capture.filter(Uint8List.fromList(utf8.encode('pty'))),
      utf8.encode('pty'),
    );
    expect(submitted, isNull);
  });

  test('backspace passes through and shrinks the buffered line', () {
    var intercept = true;
    String? submitted;
    final capture = BusUserLineCapture(
      BusUserInputRouting(
        shouldIntercept: () => intercept,
        onUserLine: (line) => submitted = line,
      ),
    );

    // "ab" then DEL then "c" → buffered line is "ac"; all bytes pass through.
    expect(
      capture.filter(Uint8List.fromList([0x61, 0x62, 0x7f, 0x63])),
      [0x61, 0x62, 0x7f, 0x63],
    );
    capture.filter(Uint8List.fromList(utf8.encode('\r')));
    expect(submitted, 'ac');
  });
}
