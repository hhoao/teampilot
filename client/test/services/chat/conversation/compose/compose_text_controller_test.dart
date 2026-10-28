import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/chat/conversation/compose/compose_text_controller.dart';
import 'package:teampilot/services/chat/conversation/compose/compose_token_document.dart';

void main() {
  test('typed @text is not a token', () {
    final controller = ComposeTextController();
    addTearDown(controller.dispose);
    controller.text = '@src/main.dart hello';
    expect(controller.document.tokens, isEmpty);
    expect(controller.tokenRanges, isEmpty);
  });

  test('insertToken registers the range, suffix stays outside', () {
    final controller = ComposeTextController();
    addTearDown(controller.dispose);
    controller.text = '/pl';
    controller.selection = const TextSelection.collapsed(offset: 3);
    controller.insertToken(
      start: 0,
      end: 3,
      tokenText: '/plan',
      kind: ComposeTokenKind.skill,
      payload: '/plan',
    );
    expect(controller.text, '/plan ');
    expect(controller.tokenRanges, [const TextRange(start: 0, end: 5)]);
  });

  test('a second token does not disturb the first', () {
    final controller = ComposeTextController();
    addTearDown(controller.dispose);
    controller.insertToken(
      start: 0,
      end: 0,
      tokenText: '/a',
      kind: ComposeTokenKind.command,
      payload: '/a',
    );
    controller.insertToken(
      start: 3,
      end: 3,
      tokenText: '/b',
      kind: ComposeTokenKind.command,
      payload: '/b',
    );
    expect(controller.text, '/a /b ');
    expect(controller.tokenRanges, [
      const TextRange(start: 0, end: 2),
      const TextRange(start: 3, end: 5),
    ]);
  });

  test('typing after a zero-argument token does not extend it', () {
    final controller = ComposeTextController();
    addTearDown(controller.dispose);
    controller.insertToken(
      start: 0,
      end: 0,
      tokenText: '/plan',
      suffix: '',
      kind: ComposeTokenKind.command,
      payload: '/plan',
    );
    controller.text = '/plan帮我看看';
    expect(controller.tokenRanges, [const TextRange(start: 0, end: 5)]);
  });

  test('editing inside a token dissolves it', () {
    final controller = ComposeTextController();
    addTearDown(controller.dispose);
    controller.insertToken(
      start: 0,
      end: 0,
      tokenText: '@a',
      suffix: '',
      kind: ComposeTokenKind.fileReference,
      payload: '@a',
    );
    controller.text = '@Xa';
    expect(controller.tokenRanges, isEmpty);
  });

  test('insertReferences creates one token per reference with separators', () {
    final controller = ComposeTextController();
    addTearDown(controller.dispose);
    controller.text = 'run';
    controller.selection = const TextSelection.collapsed(offset: 3);
    controller.insertReferences(['@a.txt', '@b.txt']);
    expect(controller.text, 'run @a.txt @b.txt ');
    expect(controller.tokenRanges, [
      const TextRange(start: 4, end: 10),
      const TextRange(start: 11, end: 17),
    ]);
  });

  test('undo restores the token document for a previous text', () {
    final controller = ComposeTextController();
    addTearDown(controller.dispose);
    controller.text = '/pl';
    controller.selection = const TextSelection.collapsed(offset: 3);
    controller.insertToken(
      start: 0,
      end: 3,
      tokenText: '/plan',
      kind: ComposeTokenKind.skill,
      payload: '/plan',
    );
    controller.text = '';
    expect(controller.tokenRanges, isEmpty);
    controller.text = '/plan ';
    expect(controller.tokenRanges, [const TextRange(start: 0, end: 5)]);
  });
}
