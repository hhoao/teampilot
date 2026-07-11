import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('terminal views keep IME text input enabled', () {
    final terminalSources = [
      File('lib/pages/chat_workbench.dart'),
      File('lib/widgets/right_tools/file_tree_panel.dart'),
    ];

    for (final sourceFile in terminalSources) {
      final source = sourceFile.readAsStringSync();

      expect(
        source,
        isNot(contains('hardwareKeyboardOnly: true')),
        reason: '${sourceFile.path} must use TextInput so Chinese IME works.',
      );
    }
  });
}
