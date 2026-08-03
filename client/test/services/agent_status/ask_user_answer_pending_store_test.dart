import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/agent_status/ask_user_answer_pending_store.dart';

void main() {
  late AskUserAnswerPendingStore store;

  setUp(() {
    store = AskUserAnswerPendingStore();
  });

  test('put then take consumes once', () {
    const entry = AskUserAnswerPendingEntry(
      requestId: 'req-1',
      answers: [
        ['yes'],
      ],
    );

    store.put(
      sessionId: 'sess-a',
      memberId: 'member-1',
      entry: entry,
    );

    expect(
      store.take(
        sessionId: 'sess-a',
        memberId: 'member-1',
        requestId: 'req-1',
      ),
      entry,
    );
    expect(
      store.take(
        sessionId: 'sess-a',
        memberId: 'member-1',
        requestId: 'req-1',
      ),
      isNull,
    );
  });

  test('take missing returns null', () {
    expect(
      store.take(
        sessionId: 'sess-a',
        memberId: 'member-1',
        requestId: 'missing',
      ),
      isNull,
    );
  });

  test('reject entry', () {
    const entry = AskUserAnswerPendingEntry(
      requestId: 'req-reject',
      reject: true,
    );

    store.put(
      sessionId: 'sess-a',
      memberId: 'member-1',
      entry: entry,
    );

    expect(
      store.take(
        sessionId: 'sess-a',
        memberId: 'member-1',
        requestId: 'req-reject',
      ),
      entry,
    );
  });

  test('clearSeat drops all for session+member', () {
    store.put(
      sessionId: 'sess-a',
      memberId: 'member-1',
      entry: const AskUserAnswerPendingEntry(requestId: 'req-1'),
    );
    store.put(
      sessionId: 'sess-a',
      memberId: 'member-1',
      entry: const AskUserAnswerPendingEntry(requestId: 'req-2'),
    );
    store.put(
      sessionId: 'sess-a',
      memberId: 'member-2',
      entry: const AskUserAnswerPendingEntry(requestId: 'req-3'),
    );

    store.clearSeat(sessionId: 'sess-a', memberId: 'member-1');

    expect(
      store.take(
        sessionId: 'sess-a',
        memberId: 'member-1',
        requestId: 'req-1',
      ),
      isNull,
    );
    expect(
      store.take(
        sessionId: 'sess-a',
        memberId: 'member-1',
        requestId: 'req-2',
      ),
      isNull,
    );
    expect(
      store.take(
        sessionId: 'sess-a',
        memberId: 'member-2',
        requestId: 'req-3',
      ),
      isNotNull,
    );
  });

  test('overwrite same requestId', () {
    store.put(
      sessionId: 'sess-a',
      memberId: 'member-1',
      entry: const AskUserAnswerPendingEntry(
        requestId: 'req-1',
        answers: [
          ['old'],
        ],
      ),
    );
    store.put(
      sessionId: 'sess-a',
      memberId: 'member-1',
      entry: const AskUserAnswerPendingEntry(
        requestId: 'req-1',
        answers: [
          ['new'],
        ],
      ),
    );

    expect(
      store.take(
        sessionId: 'sess-a',
        memberId: 'member-1',
        requestId: 'req-1',
      ),
      const AskUserAnswerPendingEntry(
        requestId: 'req-1',
        answers: [
          ['new'],
        ],
      ),
    );
  });
}
