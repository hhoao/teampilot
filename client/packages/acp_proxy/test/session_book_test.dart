import 'package:acp_proxy/acp_proxy.dart';
import 'package:test/test.dart';

void main() {
  test('a second attach returns the first connection and detach clears it', () {
    final book = AcpProxySessionBook();

    expect(book.connectionFor('missing'), isNull);
    expect(book.attach(sessionId: 's1', connectionId: 'c1'), isNull);
    expect(book.connectionFor('s1'), 'c1');

    expect(book.attach(sessionId: 's1', connectionId: 'c2'), 'c1');
    expect(book.connectionFor('s1'), 'c2');

    book.detach('c1');
    expect(book.connectionFor('s1'), 'c2');

    book.detach('c2');
    expect(book.connectionFor('s1'), isNull);
    expect(book.attach(sessionId: 's1', connectionId: 'c3'), isNull);
    expect(book.connectionFor('s1'), 'c3');
  });

  test('the same prompt joins an open turn and a different prompt throws', () {
    final book = AcpProxySessionBook();

    expect(book.turnInProgress('s1'), isFalse);
    expect(
      book.onPrompt(sessionId: 's1', text: 'hello'),
      AcpProxyPromptDisposition.start,
    );
    expect(book.turnInProgress('s1'), isTrue);
    expect(
      book.onPrompt(sessionId: 's1', text: 'hello'),
      AcpProxyPromptDisposition.joinInFlight,
    );

    expect(
      () => book.onPrompt(sessionId: 's1', text: 'other'),
      throwsStateError,
    );
    expect(book.turnInProgress('s1'), isTrue);
    expect(
      book.onPrompt(sessionId: 's1', text: 'hello'),
      AcpProxyPromptDisposition.joinInFlight,
    );

    book.finishTurn('s1');
    expect(book.turnInProgress('s1'), isFalse);
    expect(
      book.onPrompt(sessionId: 's1', text: 'hello'),
      AcpProxyPromptDisposition.start,
    );
    book.attach(sessionId: 's1', connectionId: 'c-live');
    book.finishTurn('s1');
    expect(book.turnInProgress('s1'), isFalse);
    expect(book.connectionFor('s1'), 'c-live');
    book.finishTurn('missing');
  });

  test('attach and detach keep the in-flight prompt', () {
    final book = AcpProxySessionBook();
    book.attach(sessionId: 's1', connectionId: 'c1');
    expect(
      book.onPrompt(sessionId: 's1', text: 'hello'),
      AcpProxyPromptDisposition.start,
    );

    expect(book.attach(sessionId: 's1', connectionId: 'c2'), 'c1');
    expect(book.connectionFor('s1'), 'c2');
    expect(book.turnInProgress('s1'), isTrue);
    expect(
      book.onPrompt(sessionId: 's1', text: 'hello'),
      AcpProxyPromptDisposition.joinInFlight,
    );

    book.detach('c2');
    expect(book.connectionFor('s1'), isNull);
    expect(book.turnInProgress('s1'), isTrue);
    expect(
      book.onPrompt(sessionId: 's1', text: 'hello'),
      AcpProxyPromptDisposition.joinInFlight,
    );
    book.finishTurn('s1');
    expect(book.connectionFor('s1'), isNull);
  });

  test('a different session is independent', () {
    final book = AcpProxySessionBook();
    book.attach(sessionId: 's1', connectionId: 'c1');
    book.attach(sessionId: 's2', connectionId: 'c2');
    expect(
      book.onPrompt(sessionId: 's1', text: 'hello'),
      AcpProxyPromptDisposition.start,
    );
    expect(
      book.onPrompt(sessionId: 's2', text: 'other'),
      AcpProxyPromptDisposition.start,
    );

    expect(
      () => book.onPrompt(sessionId: 's1', text: 'other'),
      throwsStateError,
    );
    expect(book.turnInProgress('s1'), isTrue);
    expect(book.turnInProgress('s2'), isTrue);

    book.finishTurn('s1');
    expect(book.turnInProgress('s1'), isFalse);
    expect(book.turnInProgress('s2'), isTrue);
    expect(
      book.onPrompt(sessionId: 's1', text: 'hello'),
      AcpProxyPromptDisposition.start,
    );
    expect(
      book.onPrompt(sessionId: 's2', text: 'other'),
      AcpProxyPromptDisposition.joinInFlight,
    );

    book.detach('c1');
    expect(book.connectionFor('s1'), isNull);
    expect(book.connectionFor('s2'), 'c2');
  });
}
