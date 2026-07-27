import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/selection_ai/selection_ai_context.dart';

void main() {
  test('buildFileAiContextClipboardText matches editor template', () {
    expect(
      buildFileAiContextClipboardText(
        relPath: 'lib/foo.dart',
        startLine: 10,
        endLine: 12,
        language: 'dart',
        code: 'void main() {}',
      ),
      'lib/foo.dart:10-12\n```dart\nvoid main() {}\n```',
    );
  });

  test('buildTerminalAiContextClipboardText without line range', () {
    expect(
      buildTerminalAiContextClipboardText(
        surfaceLabel: 'workspace-shell',
        text: 'error: boom',
      ),
      'terminal:workspace-shell\n```text\nerror: boom\n```',
    );
  });

  test('buildTerminalAiContextClipboardText with line range', () {
    expect(
      buildTerminalAiContextClipboardText(
        surfaceLabel: 'session/s1/lead',
        text: 'hi',
        startLine: 3,
        endLine: 5,
      ),
      'terminal:session/s1/lead L3-5\n```text\nhi\n```',
    );
  });

  test('buildTerminalAiContextClipboardText empty text returns empty', () {
    expect(
      buildTerminalAiContextClipboardText(
        surfaceLabel: 'workspace-shell',
        text: '  \n',
      ),
      '',
    );
  });

  test('selectionAskAiPrefillText appends blank line', () {
    expect(
      selectionAskAiPrefillText('ctx'),
      'ctx\n\n',
    );
    expect(selectionAskAiPrefillText('  '), '');
  });
}
