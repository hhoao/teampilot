import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/chat/conversation/compose/compose_file_attach.dart';
import 'package:teampilot/services/chat/conversation/compose/compose_text_controller.dart';
import 'package:teampilot/services/chat/conversation/compose/compose_text_edit.dart';
import 'package:teampilot/services/chat/conversation/compose/compose_token_document.dart';
import 'package:teampilot/services/chat/conversation/compose/compose_voice_input.dart';
import 'package:speech_to_text/speech_recognition_error.dart';

void main() {
  group('formatComposeFileReference', () {
    test('uses relative path under workspace root', () {
      expect(
        formatComposeFileReference(
          r'C:\repo\src\main.dart',
          workspaceRoot: r'C:\repo',
          usesPosixPaths: false,
        ),
        '@src/main.dart',
      );
    });

    test('uses relative POSIX path under workspace root on any host', () {
      expect(
        formatComposeFileReference(
          '/repo/docs/readme.md',
          workspaceRoot: '/repo',
          usesPosixPaths: false,
        ),
        '@docs/readme.md',
      );
    });

    test('matches workspace root case-insensitively on Windows', () {
      expect(
        formatComposeFileReference(
          r'C:\Repo\src\main.dart',
          workspaceRoot: r'c:\repo',
          usesPosixPaths: false,
        ),
        '@src/main.dart',
      );
    });

    test('keeps absolute path outside workspace root', () {
      expect(
        formatComposeFileReference(
          r'D:\other\file.txt',
          workspaceRoot: r'C:\repo',
          usesPosixPaths: false,
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

  group('insertComposeReferences', () {
    test('registers file tokens instead of parsing the text', () {
      final controller = ComposeTextController();
      addTearDown(controller.dispose);
      controller.text = 'run';
      controller.selection = const TextSelection.collapsed(offset: 3);

      insertComposeReferences(controller, ['@a.txt', '@b.txt']);

      expect(controller.text, 'run @a.txt @b.txt ');
      expect(controller.document.tokens.length, 2);
      expect(
        controller.document.tokens.every(
          (token) => token.kind == ComposeTokenKind.fileReference,
        ),
        isTrue,
      );
      expect(controller.tokenRanges, [
        const TextRange(start: 4, end: 10),
        const TextRange(start: 11, end: 17),
      ]);
    });

    test('a second call appends after existing text', () {
      final controller = ComposeTextController();
      addTearDown(controller.dispose);
      controller.text = 'hi';
      controller.selection = const TextSelection.collapsed(offset: 2);
      insertComposeReferences(controller, ['@a.txt']);
      insertComposeReferences(controller, ['@b.txt']);

      expect(controller.text, 'hi @a.txt @b.txt ');
      expect(controller.document.tokens.length, 2);
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
