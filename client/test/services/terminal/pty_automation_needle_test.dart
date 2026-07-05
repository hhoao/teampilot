import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/terminal/pty_automation_needle.dart';

void main() {
  test('forText uses bus prefix for doorbell notices', () {
    const notice =
        '[teammate-bus] You have unread teammate messages — call read_messages';
    expect(PtyAutomationNeedle.forText(notice), notice.substring(0, 40));
  });

  test('forText keeps short CJK landing text whole', () {
    const landing = '和你的队员打个招呼吧';
    expect(PtyAutomationNeedle.forText(landing), landing);
  });

  test('forText uses tail for long free-form text', () {
    final long = 'a' * 50 + 'UNIQUE_TAIL';
    expect(PtyAutomationNeedle.forText(long), endsWith('UNIQUE_TAIL'));
    expect(PtyAutomationNeedle.forText(long).length, 40);
  });
}
