import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/compose/compose_file_attach.dart';
import 'package:teampilot/services/compose/compose_text_edit.dart';
import 'package:teampilot/services/compose/compose_voice_input.dart';
import 'package:speech_to_text/speech_recognition_error.dart';

void main() {
  group('formatComposeFileReference', () {
    test('uses relative path under workspace root', () {
      expect(
        formatComposeFileReference(
          r'C:\repo\src\main.dart',
          workspaceRoot: r'C:\repo',
        ),
        '@src/main.dart',
      );
    });

    test('matches workspace root case-insensitively on Windows', () {
      expect(
        formatComposeFileReference(
          r'C:\Repo\src\main.dart',
          workspaceRoot: r'c:\repo',
        ),
        '@src/main.dart',
      );
    });

    test('keeps absolute path outside workspace root', () {
      expect(
        formatComposeFileReference(
          r'D:\other\file.txt',
          workspaceRoot: r'C:\repo',
        ),
        '@D:/other/file.txt',
      );
    });
  });

  group('insertTextAtSelection', () {
    test('inserts at cursor with separators', () {
      final controller = TextEditingController(text: 'hello');
      controller.selection = const TextSelection.collapsed(offset: 5);

      controller.value = insertTextAtSelection(
        controller,
        'world',
        separatorBefore: ' ',
        separatorAfter: ' ',
      );

      expect(controller.text, 'hello world ');
      expect(controller.selection.baseOffset, 12);
    });
  });

  group('speechRecognitionErrorIsPermissionDenied', () {
    test('detects permission-related errors', () {
      expect(
        speechRecognitionErrorIsPermissionDenied(
          SpeechRecognitionError('error_permission', true),
        ),
        isTrue,
      );
      expect(
        speechRecognitionErrorIsPermissionDenied(
          SpeechRecognitionError('not authorized', true),
        ),
        isTrue,
      );
      expect(
        speechRecognitionErrorIsPermissionDenied(
          SpeechRecognitionError('network timeout', false),
        ),
        isFalse,
      );
    });
  });
}
