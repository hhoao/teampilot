import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/chat/conversation/compose/compose_token_document.dart';

ComposeToken _token(int start, int end, {String payload = '@a'}) => ComposeToken(
  id: '$start-$end',
  kind: ComposeTokenKind.fileReference,
  start: start,
  end: end,
  payload: payload,
);

void main() {
  test('insert after token keeps the token', () {
    final doc = ComposeTokenDocument.empty.add(_token(0, 2)); // '@a '
    final next = doc.applyEdit('@a ', '@a b');
    expect(next.tokens.single.range, const TextRange(start: 0, end: 2));
  });

  test('insert before token shifts the token', () {
    final doc = ComposeTokenDocument.empty.add(_token(2, 4)); // 'x @a'
    final next = doc.applyEdit('x @a', 'xy @a');
    expect(next.tokens.single.range, const TextRange(start: 3, end: 5));
  });

  test('typing inside a token dissolves it', () {
    final doc = ComposeTokenDocument.empty.add(_token(0, 3)); // '@ab'
    expect(doc.applyEdit('@ab', '@aXb').tokens, isEmpty);
  });

  test('typing at token end keeps the token', () {
    final doc = ComposeTokenDocument.empty.add(_token(0, 3));
    expect(
      doc.applyEdit('@ab', '@abX').tokens.single.range,
      const TextRange(start: 0, end: 3),
    );
  });

  test('typing at token start keeps the token', () {
    final doc = ComposeTokenDocument.empty.add(_token(0, 3));
    expect(
      doc.applyEdit('@ab', 'X@ab').tokens.single.range,
      const TextRange(start: 1, end: 4),
    );
  });

  test('deleting the trailing space keeps the token', () {
    final doc = ComposeTokenDocument.empty.add(_token(0, 3));
    expect(
      doc.applyEdit('@ab ', '@ab').tokens.single.range,
      const TextRange(start: 0, end: 3),
    );
  });

  test('deleting into the token dissolves it', () {
    final doc = ComposeTokenDocument.empty.add(_token(0, 3));
    expect(doc.applyEdit('@ab', '@b').tokens, isEmpty);
  });

  test('replacing text after a token keeps it', () {
    final doc = ComposeTokenDocument.empty.add(_token(0, 3));
    expect(
      doc.applyEdit('@ab old', '@ab new').tokens.single.range,
      const TextRange(start: 0, end: 3),
    );
  });

  test('replacing a range that touches a token dissolves it', () {
    final doc = ComposeTokenDocument.empty.add(_token(0, 3));
    expect(doc.applyEdit('@ab old', 'new').tokens, isEmpty);
  });

  test('clearing text drops every token', () {
    final doc = ComposeTokenDocument.empty
        .add(_token(0, 3))
        .add(_token(5, 8, payload: '@c'));
    expect(doc.applyEdit('@ab @c ', '').tokens, isEmpty);
  });

  test('backspace/delete boundaries resolve whole tokens', () {
    final doc = ComposeTokenDocument.empty.add(_token(2, 5));
    expect(doc.tokenForBackspace(5)?.range, const TextRange(start: 2, end: 5));
    expect(doc.tokenForBackspace(2), isNull);
    expect(doc.tokenForDelete(2)?.range, const TextRange(start: 2, end: 5));
    expect(doc.tokenForDelete(5), isNull);
  });

  test('selection-only changes leave tokens untouched', () {
    final doc = ComposeTokenDocument.empty.add(_token(0, 2));
    expect(doc.applyEdit('@a hi', '@a hi').tokens.single.range,
        const TextRange(start: 0, end: 2));
  });
}
