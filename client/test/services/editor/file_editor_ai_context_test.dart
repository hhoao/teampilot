import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/editor/file_editor_ai_context.dart';

void main() {
  test('buildEditorAiContextClipboardText matches expected template', () {
    final text = buildEditorAiContextClipboardText(
      relPath: 'lib/foo.dart',
      startLine: 10,
      endLine: 12,
      language: 'dart',
      code: 'void main() {}',
    );
    expect(
      text,
      'lib/foo.dart:10-12\n```dart\nvoid main() {}\n```',
    );
  });
}
