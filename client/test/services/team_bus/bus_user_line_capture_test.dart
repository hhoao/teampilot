import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team_bus/bus_user_line_capture.dart';

void main() {
  test('swallows keystrokes while intercepting and submits a line to bus', () {
    var intercept = true;
    String? submitted;
    final capture = BusUserLineCapture(
      BusUserInputRouting(
        shouldIntercept: () => intercept,
        onUserLine: (line) => submitted = line,
      ),
    );

    expect(
      capture.filter(Uint8List.fromList(utf8.encode('hi\r'))),
      isEmpty,
    );
    expect(submitted, 'hi');

    submitted = null;
    intercept = false;
    expect(
      capture.filter(Uint8List.fromList(utf8.encode('pty'))),
      utf8.encode('pty'),
    );
  });
}
