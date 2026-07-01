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

  test('non-parked submit fires onTurnStart with bytes left untouched', () {
    var turnStarts = 0;
    String? submitted;
    final capture = BusUserLineCapture(
      BusUserInputRouting(
        shouldIntercept: () => false, // never parked
        onUserLine: (line) => submitted = line,
        onTurnStart: () => turnStarts++,
      ),
    );

    // Enter passes through unchanged (CLI submits normally), but the non-empty
    // line raises a turn-start edge — and nothing is routed to the inbox.
    expect(
      capture.filter(Uint8List.fromList(utf8.encode('do it\r'))),
      utf8.encode('do it\r'),
    );
    expect(turnStarts, 1);
    expect(submitted, isNull);
  });

  test('non-parked bare Enter (empty line) does not fire onTurnStart', () {
    var turnStarts = 0;
    final capture = BusUserLineCapture(
      BusUserInputRouting(
        shouldIntercept: () => false,
        onUserLine: (_) => '',
        onTurnStart: () => turnStarts++,
      ),
    );

    expect(
      capture.filter(Uint8List.fromList(utf8.encode('\r'))),
      utf8.encode('\r'),
    );
    expect(turnStarts, 0);
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

  test('decodes UTF-8 multibyte input instead of Latin-1 per-byte', () {
    String? submitted;
    final capture = BusUserLineCapture(
      BusUserInputRouting(
        shouldIntercept: () => true,
        onUserLine: (line) => submitted = line,
      ),
    );

    capture.filter(Uint8List.fromList(utf8.encode('你好\r')));
    expect(submitted, '你好');

    submitted = null;
    capture.filter(Uint8List.fromList(utf8.encode('hello你好\r')));
    expect(submitted, 'hello你好');
  });

  test('backspace shrinks UTF-8 characters, not raw bytes', () {
    String? submitted;
    final capture = BusUserLineCapture(
      BusUserInputRouting(
        shouldIntercept: () => true,
        onUserLine: (line) => submitted = line,
      ),
    );

    // 你 → backspace → 好 → submit → "好"
    capture.filter(Uint8List.fromList(utf8.encode('你')));
    capture.filter(Uint8List.fromList([0x7f]));
    capture.filter(Uint8List.fromList(utf8.encode('好\r')));
    expect(submitted, '好');

    submitted = null;
    // Leading byte of a multibyte char, then DEL — pending cleared, not garbled.
    capture.filter(Uint8List.fromList([0xE4, 0x7f]));
    capture.filter(Uint8List.fromList(utf8.encode('好\r')));
    expect(submitted, '好');
  });
}
