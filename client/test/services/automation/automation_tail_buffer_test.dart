import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/automation/automation_tail_buffer.dart';

void main() {
  test('keeps everything under the limit', () {
    final buffer = AutomationTailBuffer(maxBytes: 16);
    buffer.add('hello ');
    buffer.add('world');
    expect(buffer.text, 'hello world');
    expect(buffer.truncated, isFalse);
  });

  test('keeps only the tail and flags truncation', () {
    final buffer = AutomationTailBuffer(maxBytes: 8);
    buffer.add('abcdefghij');
    expect(buffer.text, 'cdefghij');
    expect(buffer.truncated, isTrue);
  });

  test('does not split multi-byte characters', () {
    final buffer = AutomationTailBuffer(maxBytes: 4);
    buffer.add('中文测试');
    expect(buffer.text.endsWith('试'), isTrue);
    expect(buffer.text.contains('\uFFFD'), isFalse);
    expect(buffer.truncated, isTrue);
  });
}
