import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/utils/first_user_line_capture.dart';

void main() {
  test('submits first non-empty line on Enter', () {
    String? submitted;
    final capture = FirstUserLineCapture((line) => submitted = line);
    capture.feed('Hello');
    capture.feed('\r');
    expect(submitted, 'Hello');
    expect(capture.isCompleted, isTrue);
  });

  test('ignores empty submits until text is entered', () {
    String? submitted;
    final capture = FirstUserLineCapture((line) => submitted = line);
    capture.feed('\n');
    capture.feed('\r\n');
    expect(submitted, isNull);
    capture.feed('Hi');
    capture.feed('\n');
    expect(submitted, 'Hi');
  });

  test('fires at most once', () {
    var count = 0;
    final capture = FirstUserLineCapture((_) => count++);
    capture.feed('one\r');
    capture.feed('two\r');
    expect(count, 1);
  });

  test('handles backspace', () {
    String? submitted;
    final capture = FirstUserLineCapture((line) => submitted = line);
    capture.feed('ab\x7f');
    capture.feed('\r');
    expect(submitted, 'a');
  });

  test('ignores CSI device-attribute response before user text', () {
    String? submitted;
    final capture = FirstUserLineCapture((line) => submitted = line);
    // xterm focus: ESC [ ? 1 ; 2 c  then user types hello
    capture.feed('\x1b[?1;2chello\r');
    expect(submitted, 'hello');
  });
}
