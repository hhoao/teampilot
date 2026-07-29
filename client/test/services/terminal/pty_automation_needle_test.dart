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

  test('forText flattens newlines so multiline paste tails can grid-ACK', () {
    // Long JSON tails are mostly closing braces + newlines. Grid cells never
    // contain CR/LF, so a raw tail needle can never match the mirror.
    const jsonTail = '''
         }
        }
      }
    }
  ]
}''';
    final needle = PtyAutomationNeedle.forText('prefix$jsonTail');
    expect(needle.contains('\n'), isFalse);
    expect(needle.contains('\r'), isFalse);
    expect(needle, contains('}'));
    expect(needle.length, lessThanOrEqualTo(PtyAutomationNeedle.maxNeedleChars));
  });

  test('collapsedPasteNeedle extracts Claude Code paste chrome', () {
    const row = '❯ [Pasted text #3 +17 lines]';
    expect(
      PtyAutomationNeedle.collapsedPasteNeedle(row),
      '[Pasted text #3 +17 lines]',
    );
  });

  test('collapsedPasteNeedle accepts singular line', () {
    expect(
      PtyAutomationNeedle.collapsedPasteNeedle('[Pasted text #1 +1 line]'),
      '[Pasted text #1 +1 line]',
    );
  });

  test('collapsedPasteNeedle returns null when absent', () {
    expect(PtyAutomationNeedle.collapsedPasteNeedle('❯ hello world'), isNull);
  });
}
