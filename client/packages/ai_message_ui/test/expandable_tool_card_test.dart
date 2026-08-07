import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('card tap calls onToggle; child exclusive tap does not', (tester) async {
    var toggles = 0;
    var childTaps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiExpandableToolCard(
            open: false,
            onToggle: () => toggles++,
            child: Column(
              children: [
                const Text('card-body'),
                GestureDetector(
                  onTap: () => childTaps++,
                  behavior: HitTestBehavior.opaque,
                  child: const Text('exclusive'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('card-body'));
    await tester.pump();
    expect(toggles, 1);
    await tester.tap(find.text('exclusive'));
    await tester.pump();
    expect(childTaps, 1);
    expect(toggles, 1);
  });

  test('previewToolCardText keeps first 5 lines of multi-line string', () {
    final text = 'line1\nline2\nline3\nline4\nline5\nline6\nline7';
    expect(previewToolCardText(text), 'line1\nline2\nline3\nline4\nline5');
  });

  test('previewToolCardText returns full text when within line cap', () {
    const text = 'line1\nline2\nline3';
    expect(previewToolCardText(text), text);
  });

  test('capToolPanelText keeps head + marker beyond maxChars', () {
    final text = List.generate(20, (_) => 'x' * 4000).join('\n'); // 80 KB
    final capped = capToolPanelText(text, maxChars: 50000);
    expect(capped.length, lessThan(50000 + 100));
    expect(capped.contains(kAiToolPanelTruncationMarker), isTrue);
    expect(capped.startsWith('xxxx'), isTrue);
  });

  test('capToolPanelText returns full text within maxChars', () {
    const text = 'small output';
    expect(capToolPanelText(text), text);
  });
}
